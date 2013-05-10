/* ts=4 */
/*
** Copyright 2011 Carnegie Mellon University
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
 @file SnewContext.c
 @brief Implements SnewContext()
*/

#include "session.h"
#include "Sutil.h"
#include <errno.h>

int SnewContext()
{
	int rc;
	int sockfd;


	// Open socket to session process
	if ((sockfd = socket(AF_INET, SOCK_DGRAM, 0)) == -1) {
		LOGF("error creating socket to session process: %s", strerror(errno));
		return -1;
	}

	struct sockaddr_in addr;
	addr.sin_family = PF_INET;
	addr.sin_addr.s_addr = inet_addr("127.0.0.1");
	addr.sin_port = 0;

	if (bind(sockfd, (const struct sockaddr *)&addr, sizeof(addr)) < 0) {
		close(sockfd);
		LOGF("bind error: %s", strerror(errno));
		return -1;
	}
		
	// protobuf message
	session::SessionMsg sm;
	sm.set_type(session::NEW_CONTEXT);
	//session::S_New_Context_Msg *ncm = sm.mutable_s_new_context(); // TODO: don't need this?
	
	if ((rc = click_send(sockfd, &sm)) < 0) {
		LOGF("Error talking to session proc: %s", strerror(errno));
		close(sockfd);
		return -1;
	}

	// process the reply from the session process
	session::SessionMsg rsm;
	if ((rc = click_reply(sockfd, rsm)) < 0) {
		LOGF("Error getting status from session proc: %s", strerror(errno));
	} 
	if (rsm.type() != session::RETURN_CODE || rsm.s_rc().rc() != session::SUCCESS) {
		LOG("Session proc returned an error");
		rc = -1;
	}
	
	if (rc == 0) {
		return sockfd; // for now, treat the sockfd as the context handle
	}

	// close the control socket since the underlying Xsocket is no good
	close(sockfd);
	return -1; 
}
