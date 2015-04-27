/* ts=4 */
/*
** Copyright 2012 Carnegie Mellon University
**
** Licensed under the Apache License, Version 2.0 (the "License");
** you may not use this file except in compliance with the License.
** You may obtain a copy of the License at
**
**    http://www.apache.org/licenses/LICENSE-2.0
**
** Unless required by applicable law or agreed to in writing, software
** distributed under the License is distributed on an "AS IS" BASIS,
** WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
** See the License for the specific language governing permissions and
** limitations under the License.
*/
/*!
  @file state.c
  @brief implements internal socket state functionality.
*/
#include <map>
#include <string>
#include <pthread.h>
#include <string.h>
#include <assert.h>
#include "Xsocket.h"
#include "Xinit.h"
#include "Xutil.h"

using namespace std;

class SocketState
{
public:
	SocketState();
	SocketState(int tt);
	~SocketState();

	int transportType() { return m_transportType; };
	void setTransportType(int tt) {m_transportType = tt; };

	int protocol() { return m_protocol; };
	void setProtocol(int p) {m_protocol = p; };

	int getConnState() { return m_connected; };
	void setConnState(int conn) { m_connected = conn; };

	int isBlocking() { return m_blocking; };
	void setBlocking(int blocking) { m_blocking = blocking; };

	unsigned seqNo();

	int getPacket(unsigned seq, char *buf, unsigned buflen);
	void insertPacket(unsigned seq, char *buf, unsigned buflen);

	void setDebug(int debug) { m_debug = debug; };
	int getDebug() { return m_debug; };

	void setRecvTimeout(struct timeval *timeout) { m_timeout.tv_sec = timeout->tv_sec; m_timeout.tv_usec = timeout->tv_usec; };
	void getRecvTimeout(struct timeval *timeout) {timeout->tv_sec = m_timeout.tv_sec; timeout->tv_usec = m_timeout.tv_usec; };

	void setError(int error) { m_error = error; };
	int getError() { int e = m_error; m_error = 0;return e; };
//	int getError() { int e = m_error; m_error = 0; return e; };

	const sockaddr_x *peer() { return m_peer; };
	int setPeer(const sockaddr_x *peer);

	int isSIDAssigned() { return m_sid_assigned; };
	void setSIDAssigned() { m_sid_assigned = 1; };

	int isTempSID() { return (m_temp_sid == NULL) ? 0 : 1;};
	void setTempSID(const char *sid);
	const char *getTempSID() {return m_temp_sid;};

	void init();
private:
	int m_transportType;
	int m_protocol;
	int m_connected;
	int m_blocking;
	int m_debug;
	int m_error;
	sockaddr_x *m_peer;
	char *m_temp_sid;
	int m_sid_assigned;
	unsigned m_sequence;
	struct timeval m_timeout;
	pthread_mutex_t m_sequence_lock;
	map<unsigned, string> m_packets;


};

SocketState::SocketState(int tt)
{
	init();
	m_transportType = tt;
}

SocketState::SocketState()
{
	init();
}

SocketState::~SocketState()
{
	if (m_peer)
		free(m_peer);
	m_packets.clear();
	pthread_mutex_destroy(&m_sequence_lock);
}

void SocketState::init()
{
	m_transportType = -1;
	m_protocol = 0;
	m_connected = 0;
	m_blocking = TRUE;
	m_peer = NULL;
	m_temp_sid = NULL;
	m_sid_assigned = 0;
	m_sequence = 1;
	m_debug = 0;
	m_error = 0;
	m_timeout.tv_sec = 0;
	m_timeout.tv_usec = 0;
	pthread_mutex_init(&m_sequence_lock, NULL);
}

void SocketState::setTempSID(const char *sid)
{
	if(!sid) {
		return;
	}
	if(m_temp_sid) {
		delete(m_temp_sid);
	}
	m_temp_sid = new char [strlen(sid) + 1];
	if(!m_temp_sid) {
		return;
	}
	strcpy(m_temp_sid, sid);
}

int SocketState::getPacket(unsigned seq, char *buf, unsigned buflen)
{
	int rc = 0;
	map<unsigned, string>::iterator it;

	it = m_packets.find(seq);
	if (it != m_packets.end()) {
		string s = it->second;

printf("getting a packet\n");
		rc = MIN(buflen, s.size());
		memcpy(buf, s.c_str(), rc);

		m_packets.erase(seq);
	}

	return rc;
}

void SocketState::insertPacket(unsigned seq, char *buf, unsigned buflen)
{
	std::string s(buf, buflen);
	m_packets[seq] = s;
}

unsigned SocketState::seqNo()
{ 
	pthread_mutex_lock(&m_sequence_lock);
	unsigned seq = m_sequence++;
	pthread_mutex_unlock(&m_sequence_lock);

	return seq; 
}

class SocketMap
{
public:
	~SocketMap();

	static SocketMap *getMap();

	void add(int sock, int tt);
	void remove(int sock);
	SocketState *get(int sock);

private:
	SocketMap();

	map<int, SocketState *> sockets;
	pthread_rwlock_t rwlock;

	static SocketMap *instance;
};

SocketMap::SocketMap()
{
	pthread_rwlock_init(&rwlock, NULL);
}

SocketMap::~SocketMap()
{
	pthread_rwlock_destroy(&rwlock);
}

SocketMap *SocketMap::instance = (SocketMap *)0;

SocketMap *SocketMap::getMap()
{
	static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;

	if (!instance) {

		pthread_mutex_lock(&lock);

		if (!instance)
			instance = new SocketMap();

		pthread_mutex_unlock(&lock);
	}
	return instance;
}

void SocketMap::add(int sock, int tt)
{
	SocketMap *state = getMap();
	pthread_rwlock_wrlock(&rwlock);
	if (state->sockets[sock] == 0)
		state->sockets[sock] = new SocketState(tt);
	pthread_rwlock_unlock(&rwlock);
}

void SocketMap::remove(int sock)
{
	SocketMap *state = getMap();

	pthread_rwlock_wrlock(&rwlock);
	delete state->sockets[sock];
	state->sockets.erase(sock);
	pthread_rwlock_unlock(&rwlock);
}

SocketState *SocketMap::get(int sock)
{
	// because a socket will only be acted on by one thread at a time,
	// we don't need to be more protective of the stat structure

	pthread_rwlock_rdlock(&rwlock);
	SocketState *p =  SocketMap::getMap()->sockets[sock];
	pthread_rwlock_unlock(&rwlock);
	return p;
}

int SocketState::setPeer(const sockaddr_x *peer)
{
	if (m_peer != NULL) {
		free(m_peer);
		m_peer = NULL;
	}

	if (peer) {
		m_peer = (sockaddr_x *)malloc(sizeof(sockaddr_x));
		memcpy(m_peer, peer, sizeof(sockaddr_x));
	}
	return 0;
}

// extern "C" {

void allocSocketState(int sock, int tt)
{
	SocketMap::getMap()->add(sock, tt);
}

void freeSocketState(int sock)
{
	SocketMap::getMap()->remove(sock);
}

int getSocketType(int sock)
{
	SocketState *sstate = SocketMap::getMap()->get(sock);
	if (sstate) {
		return sstate->transportType();
	}
	else
		return -1;
}

int getProtocol(int sock)
{
	SocketState *sstate = SocketMap::getMap()->get(sock);
	if (sstate) {
		return sstate->protocol();
	}
	else
		return 0;
}

int getConnState(int sock)
{
	SocketState *sstate = SocketMap::getMap()->get(sock);
	if (sstate)
		return sstate->getConnState();
	else
		return UNKNOWN_STATE;
}

void setConnState(int sock, int conn)
{
	SocketState *sstate = SocketMap::getMap()->get(sock);
	if (sstate)
		sstate->setConnState(conn);
}

int isSIDAssigned(int sock)
{
	SocketState *sstate = SocketMap::getMap()->get(sock);
	if (sstate)
		return sstate->isSIDAssigned();
	else
		return 0;
}

void setSIDAssigned(int sock)
{
	SocketState *sstate = SocketMap::getMap()->get(sock);
	if (sstate)
		sstate->setSIDAssigned();
}

int isBlocking(int sock)
{
	SocketState *sstate = SocketMap::getMap()->get(sock);
	if (sstate)
		return sstate->isBlocking();
	else
		return TRUE;
}

void setBlocking(int sock, int blocking)
{
	SocketState *sstate = SocketMap::getMap()->get(sock);
	if (sstate)
		sstate->setBlocking(blocking);
}

int getDebug(int sock)
{
	SocketState *sstate = SocketMap::getMap()->get(sock);
	if (sstate)
		return sstate->getDebug();
	else
		return 0;
}

void setDebug(int sock, int debug)
{
	SocketState *sstate = SocketMap::getMap()->get(sock);
	if (sstate)
		sstate->setDebug(debug);
}

void setRecvTimeout(int sock, struct timeval *timeout)
{
	SocketState *sstate = SocketMap::getMap()->get(sock);
	if (sstate)
		sstate->setRecvTimeout(timeout);
}

void getRecvTimeout(int sock, struct timeval *timeout)
{
	SocketState *sstate = SocketMap::getMap()->get(sock);
	if (sstate)
		sstate->getRecvTimeout(timeout);
	else
		timeout->tv_sec = timeout->tv_usec = 0;
}

void setError(int sock, int error)
{
	SocketState *sstate = SocketMap::getMap()->get(sock);
	if (sstate)
		sstate->setError(error);
}

int getError(int sock)
{
	SocketState *sstate = SocketMap::getMap()->get(sock);
	if (sstate)
		return sstate->getError();
	else
		return 0;
}

void setSocketType(int sock, int tt)
{
	SocketState *sstate = SocketMap::getMap()->get(sock);
	if (sstate)
		sstate->setTransportType(tt);
}

void setProtocol(int sock, int p)
{
	SocketState *sstate = SocketMap::getMap()->get(sock);
	if (sstate)
		sstate->setProtocol(p);
}

int isTempSID(int sock)
{
	SocketState *sstate = SocketMap::getMap()->get(sock);
	if(sstate) {
		return sstate->isTempSID();
	} else {
		return 0;
	}
}

void setTempSID(int sock, const char *sid)
{
	SocketState *sstate = SocketMap::getMap()->get(sock);
	if(sstate) {
		sstate->setTempSID(sid);
	}
}

const char *getTempSID(int sock)
{
	SocketState *sstate = SocketMap::getMap()->get(sock);
	if(sstate) {
		return sstate->getTempSID();
	}
	return NULL;
}

unsigned seqNo(int sock)
{
	SocketState *sstate = SocketMap::getMap()->get(sock);
	if (sstate)
		return sstate->seqNo();
	else
		return 0;
}

void cachePacket(int sock, unsigned seq, char *buf, unsigned buflen)
{
printf("adding cached packet\n");
	SocketState *sstate = SocketMap::getMap()->get(sock);
	if (sstate) {
		sstate->insertPacket(seq, buf, buflen);
	}
}

int getCachedPacket(int sock, unsigned seq, char *buf, unsigned buflen)
{
	int rc = 0;
	SocketState *sstate = SocketMap::getMap()->get(sock);

	if (sstate) {
		rc = sstate->getPacket(seq, buf, buflen);
	}

	return rc;
}

int connectDgram(int sock, sockaddr_x *addr)
{
	int rc = 0;
	SocketState *sstate = SocketMap::getMap()->get(sock);

	if (sstate) {
		sstate->setConnState((addr == NULL) ? UNCONNECTED : CONNECTED);
		sstate->setPeer(addr);
	}

	return rc;
}

const sockaddr_x *dgramPeer(int sock)
{
	const sockaddr_x *peer = NULL;

	SocketState *sstate = SocketMap::getMap()->get(sock);
	if (sstate)
		peer = sstate->peer();
	return peer;
}
