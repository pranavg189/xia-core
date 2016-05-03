#!/usr/bin/env bash
#

ORIGPATH=$PATH
BUILDROOT="/opt/buildroot-2013.11/output/host/usr/"
BUILDROOTBIN="$BUILDROOT/bin"
BUILDROOTPYTHONLIB="$BUILDROOT/lib/python2.7/"

pushd () {
	command pushd $1> /dev/null
	if [ $? -ne 0 ]; then
		echo "Failed to switch to $1"
		exit -1
	fi
}

popd () {
	command popd > /dev/null
	if [ $? -ne 0 ]; then
		echo "Mismatched popd"
		exit -1
	fi
}

make_sandbox () {
	echo "$1: creating sandbox"
	mkdir -p arada/sandbox-$1
	if [ $? -ne 0 ]; then
		echo "$1: Failed creating arada/sandbox-$1. Aborting."
		exit -1
	fi
}

get_source () {
	pushd arada/sandbox-$1

	echo "$1: retrieving source from distro"
	apt-get source $1 &> ${1}_source.log
	if [ $? -ne 0 ]; then
		echo "$1: Failed getting $1 source package for your distro. Aborting."
		exit -1
	fi
	sudo apt-get -y build-dep $1 &> ${1}_build_dep.log
	if [ $? -ne 0 ]; then
		echo "$!: Failed getting build dependencies. Aborting"
		exit -1
	fi
	popd
}

# NOTE: Assumes being called from arada/sandbox-$1/$1-* directory
configure () {
	configure_command=$2
	$configure_command &> ${1}_configure.log
	if [ $? -ne 0 ]; then
		echo $configure_command
		echo "$1: ERROR: Failed to configure. Aborting"
		exit -1
	fi
}

build () {
	make_args=$2
	if [ -z "$make_args" ]; then
		make &> ${1}_cross_build.log
	else
		make "$make_args" &> ${1}_cross_build.log
	fi

	if [ $? -ne 0 ]; then
		echo make $make_args
		echo "$1: ERROR: Failed to build. Aborting"
		exit -1
	fi
}

make_install () {
	install_command=$2
	sudo PATH=$PATH $install_command &> ${1}_cross_install.log
	if [ $? -ne 0 ]; then
		echo "$1: ERROR: Failed installing. Aborting"
		exit -1
	fi
}

configure_build_and_install () {
	pkgname=$1
	configure_command=$2
	echo "$pkgname: preparing to build"
	pushd arada/sandbox-$1/$1-*
	configure $pkgname "$2"
	echo "$pkgname: building"
	build $pkgname
	echo "$pkgname: installing"
	make_install $pkgname "make install"
	popd
}


exists_sandbox () {
	if [ -d arada/sandbox-$1 ]; then
		echo "$1: sandbox exists."
		return 0
	else
		return 1
	fi
}

check_and_build () {
	if exists_sandbox $1; then echo "Skipping $1 build"; else
		make_sandbox $1
		get_source $1
		configure_build_and_install $1 "$2"
	fi
}

build_native_python () {
	pkgname=$1
	python ./setup.py "build"
}

check_and_build_python_native () {
	if exists_sandbox $1; then echo "Skipping $1 build"; else
		make_sandbox $1
		get_source $1
		pushd arada/sandbox-$1/$1-*
		build_native_python $1
		popd
	fi
}

install_python () {
	pushd arada/sandbox-$1/$1-*
	sudo cp -ax build/lib.linux-x86_64-2.7/* $BUILDROOTPYTHONLIB
	popd
}

# Prime sudo
echo "Priming sudo so you don't have to enter a password multiple times"
sudo echo "Thanks!"

echo "***"
echo "*** NOTE: Do not store arada stuff on a public location"
echo "***"
sleep 5
echo ""
echo "Updating your distro."
echo "Needed to ensure correct source packages are cross-compiled."
sleep 5
sudo apt-get update &> apt-get_update.log
if [ $? -ne 0 ]; then
    echo "Failed to update package database for your distro. Aborting"
    exit -1
fi

sudo apt-get -y upgrade &> apt-get_upgrade.log
if [ $? -ne 0 ]; then
    echo "Failed to update packages for your distro. Aborting"
    exit -1
fi

if [ ! -f arada.tar.gz ]; then
    echo "ERROR: arada.tar.gz not in current directory. Aborting"
    exit -1
else
    echo "Found arada tarball"
fi

# Unpack the arada tarball
if [ -d arada ]; then
    echo "arada directory exists. Skipped unpacking arada.tar.gz"
else
    tar xzf arada.tar.gz
    if [ $? -ne 0 ]; then
        echo "ERROR: Unable to unpack arada.tar.gz. Aborting"
        exit -2
    else
        echo "Unpacked arada tarball"
    fi
fi

# Verify we have the toolchain tarball
pushd arada/toolchain

if [ ! -f LocoMate_tlcn_64bit.tar.bz2 ]; then
    echo "ERROR: toolchain tarball missing: LocoMate_tlcn_64bit.tar.bz2"
    exit -3
else
    echo "LocoMate 64-bit toolchain tarball found"
fi

# Verify that the toolchain is not already installed
if [ -d "/opt/buildroot-2013.11" ]; then
    echo "Toolchain already in /opt/buildroot-2013.11. Skipping..."
else
    echo "Installing toolchain in /opt/buildroot-2013.11"

    # Install the toolchain
    echo "Installing toolchain using sudo. Need your password:"
    sudo tar -Pjxvf LocoMate_tlcn_64bit.tar.bz2 &> locomate_unpack.log
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to unpack locomate toolchain"
        exit -5
    else
        echo "Toolchain installation complete"
    fi
fi

# Return to the directory we started from
popd #arada/toolchain

# Build protobuf
if [ ! -f "/usr/bin/protoc" ]; then
    echo "Please install protubuf-compiler, libprotobuf-dev and python-protobuf"
    echo "ERROR: /usr/bin/protoc not found. Aborting"
    exit -1
fi

PROTOCPATH=`which protoc`
export PATH=$BUILDROOTBIN/:$PATH
configure_command="./configure --host=mips-linux --prefix=/opt/buildroot-2013.11/output/host/usr/ --with-protoc=$PROTOCPATH"
check_and_build protobuf "$configure_command"
export PATH=$ORIGPATH
unset PROTOCPATH

# Build openssl
export PATH=$ORIGPATH:$BUILDROOT
export CC=/opt/buildroot-2013.11/output/host/usr/bin/mips-linux-gcc
configure_command='./Configure shared no-ssl2 --prefix=/opt/buildroot-2013.11/output/host/usr/ linux-mips32'
check_and_build openssl "$configure_command"
unset CC
export PATH=$ORIGPATH

# Build python
if exists_sandbox python2.7; then echo "Skipping python2.7 build"; else
	make_sandbox python2.7
	get_source python2.7
	pushd arada/sandbox-python2.7/python2.7-*
	echo "python2.7: Native build first"
	# Build for native host first
	configure python2.7 "./configure"
	build python2.7 "python"
	build python2.7 "Parser/pgen"
	mv python{,_for_build}
	mv Parser/pgen{,_for_build}
	# Now build for the mips target
	echo "python2.7: enabling additional modules"
	sed "s/if ext.name in sys.builtin_module_names:/if ext.name in ('__builtin__', '__main__', '_ast', '_codecs', '_sre', '_symtable', '_warnings', '_weakref', 'errno', 'exceptions', 'gc', 'imp', 'marshal', 'posix', 'pwd', 'signal', 'sys', 'thread', 'xxsubtype', 'zipimport'):/" setup.py > setup.py.new
	mv setup.py setup.py.orig
	mv setup.py.new setup.py
	echo "python2.7: Cross-compilation next"
	export PATH=$ORIGPATH:$BUILDROOTBIN
	configure_command="./configure --host=mips-linux --build=x86_64-linux-gnu --prefix=/opt/buildroot-2013.11/output/host/usr/ --disable-ipv6 ac_cv_file__dev_ptmx=no ac_cv_file__dev_ptc=no ac_cv_have_long_long_format=yes"
	configure python2.7 "$configure_command"
	# Haven't figured out how to send this command to the 'build' function
	make CFLAGS="-g0 -s -O2 -march=24kc -fomit-frame-pointer -fPIC -fdata-sections -ffunction-sections -pipe -L/opt/buildroot-2013.11/output/host/usr/lib/" &> python2.7_cross_build.log
	if [ $? -ne 0 ]; then 
		echo "Failed to build. Amorting."
		exit -1
	fi
	install_command="make install"
	make_install python2.7 "$install_command"
	popd # arada/sandbox-python2.7/python2.7-*
	export PATH=$ORIGPATH
	unset CFLAGS
fi

# coreutils
if exists_sandbox coreutils; then echo "Skipping coreutils build"; else
	make_sandbox coreutils
	get_source coreutils
	echo "coreutils: preparing to build"
	pushd arada/sandbox-coreutils/coreutils-*
	export PATH=$ORIGPATH:$BUILDROOTBIN
	configure_command="./configure --host=mips-linux --prefix=/opt/buildroot-2013.11/output/host/usr/"
	configure coreutils "$configure_command"
	# Update makefile
	sed -i.orig "s/\(^run_help2man = .*\)/\1 --no-discard-stderr/" Makefile
	if [ $? -ne 0 ]; then
		echo "coreutils: failed to update Makefile with needed fix"
		exit -1
	fi
	echo "coreutils: building"
	build coreutils
	echo "coreutils: installing"
	make_install coreutils "make install"
	export PATH=$ORIGPATH
	popd # arada/sandbox-coreutils/coreutils-*
fi

# Build libffi needed by python-cffi, needed by PyNaCl
export PATH=$ORIGPATH:$BUILDROOTBIN
configure_command="./configure --host=mips-linux --prefix=/opt/buildroot-2013.11/output/host/usr/"
check_and_build libffi "$configure_command"
export PATH=$ORIGPATH

# bash
export PATH=$ORIGPATH:$BUILDROOTBIN
configure_command="./configure --host=mips-linux --prefix=/opt/buildroot-2013.11/output/host/usr/"
check_and_build bash "$configure_command"
export PATH=$ORIGPATH

# Build and install python six
check_and_build_python_native six
install_python six

# Build python-cffi
check_and_build_python_native python-cffi
pushd arada/sandbox-python-cffi/python-cffi-*
export PATH=$ORIGPATH:$BUILDROOTBIN

mips-linux-gcc -pthread -DNDEBUG -g -fwrapv -O2 -Wall -Wstrict-prototypes -fno-strict-aliasing -D_FORTIFY_SOURCE=2 -g -Wformat -Werror=format-security -fPIC -DUSE__THREAD -I/opt/buildroot-2013.11/output/host/usr/include -I/opt/buildroot-2013.11/output/host/usr/include/python2.7 -L/opt/buildroot-2013.11/output/host/usr/lib -c c/_cffi_backend.c -o build/temp.linux-x86_64-2.7/c/_cffi_backend.o

mips-linux-gcc -pthread -shared -Wl,-O1 -Wl,-Bsymbolic-functions -Wl,-Bsymbolic-functions -Wl,-z,relro -fno-strict-aliasing -DNDEBUG -g -fwrapv -O2 -Wall -Wstrict-prototypes -D_FORTIFY_SOURCE=2 -g -Wformat -Werror=format-security -Wl,-Bsymbolic-functions -Wl,-z,relro -D_FORTIFY_SOURCE=2 -g -Wformat -Werror=format-security -L/opt/buildroot-2013.11/output/host/usr/lib build/temp.linux-x86_64-2.7/c/_cffi_backend.o -lffi -o build/lib.linux-x86_64-2.7/_cffi_backend.so

export PATH=$ORIGPATH
popd

install_python python-cffi

# Build and install libsodium
if exists_sandbox libsodium; then echo "Skipping libsodium build"; else
	make_sandbox libsodium
	get_source libsodium
	export PATH=$ORIGPATH:$BUILDROOTBIN
	pkgname=libsodium
	echo "$pkgname: preparing to build"
	pushd arada/sandbox-$pkgname/$pkgname-*
	./autogen.sh &> libsodium_autogen.log
	if [ $? -ne 0 ]; then
		echo "Failed to run autogen for $pkgname. Aborting"
		exit -1
	fi
	configure_command="./configure --host=mips-linux --prefix=/opt/buildroot-2013.11/output/host/usr/"
	configure $pkgname "$configure_command"
	echo "$pkgname: building"
	build $pkgname
	echo "$pkgname: installing"
	make_install $pkgname "make install"
	popd # arada/sandbox-libsodium/libsodium-*
	export PATH=$ORIGPATH
fi

# Build pynacl a.k.a python-nacl in Ubuntu
if exists_sandbox pynacl; then echo "Skipping pynacl build"; else
	export PATH=$ORIGPATH:$BUILDROOTBIN
	export SODIUM_INSTALL=system

	make_sandbox pynacl
	pushd arada/sandbox-pynacl/
	wget https://github.com/pyca/pynacl/archive/1.0.1.tar.gz
	tar xzf *.tar.gz
	popd
	pushd arada/sandbox-pynacl/pynacl-*/

	build_native_python pynacl

	mips-linux-gcc -pthread -DNDEBUG -g -fwrapv -O2 -Wall -Wstrict-prototypes -fno-strict-aliasing -D_FORTIFY_SOURCE=2 -g -Wformat -Werror=format-security -fPIC -I/opt/buildroot-2013.11/output/host/usr/include/python2.7 -I/opt/buildroot-2013.11/output/host/usr/include -c build/temp.linux-x86_64-2.7/_sodium.c -o build/temp.linux-x86_64-2.7/build/temp.linux-x86_64-2.7/_sodium.o

	mips-linux-gcc -pthread -shared -Wl,-O1 -Wl,-Bsymbolic-functions -Wl,-Bsymbolic-functions -Wl,-z,relro -fno-strict-aliasing -DNDEBUG -g -fwrapv -O2 -Wall -Wstrict-prototypes -D_FORTIFY_SOURCE=2 -g -Wformat -Werror=format-security -Wl,-Bsymbolic-functions -Wl,-z,relro -D_FORTIFY_SOURCE=2 -g -Wformat -Werror=format-security -L/opt/buildroot-2013.11/output/host/usr/lib build/temp.linux-x86_64-2.7/build/temp.linux-x86_64-2.7/_sodium.o -lsodium -o build/lib.linux-x86_64-2.7/nacl/_sodium.so

	popd # arada/sandbox-pynacl/pynacl-*
	export PATH=$ORIGPATH
	unset SODIUM_INSTALL

	install_python pynacl
fi

# Copy arada libraries and headers to buildroot
echo "Copying Arada wave headers to /opt/buildroot"
sudo cp -ax arada/code/include /opt/buildroot-2013.11/output/host/usr/include/arada
if [ $? -ne 0 ]; then
    echo "ERROR: copying Arada headers to /opt/buildroot.../usr/include/arada"
    exit -20
fi

echo "Copying Arada wave libraries to /opt/buildroot"
sudo cp -ax arada/code/mips/lib/* /opt/buildroot-2013.11/output/host/usr/lib/
if [ $? -ne 0 ]; then
    echo "ERROR: copying Arada libs to /opt/buildroot.../usr/lib/"
    exit -21
fi

echo "Cross-compile toolchain setup complete."
echo ""
echo ""
echo "Building XIA"
export PATH=$ORIGPATH:$BUILDROOTBIN
git pull
if [ $? -ne 0 ]; then
	echo "Failed to git pull"
	exit -1
fi
make clean
tarch=mips ./configure
if [ $? -ne 0 ]; then
	echo "Failed to configure XIA"
	exit -1
fi
make
if [ $? -ne 0 ]; then
	echo "Failed to build XIA"
	exit -1
fi
if [ -z "$BUILDROOT" ]; then
	echo "BUILDROOT variable not set. Aborting xia-core installation"
	exit -1
fi
sudo mkdir -p $BUILDROOT/xia-core
sudo cp -ax api applications bin click click-2.0.1 daemons etc $BUILDROOT/xia-core
export PATH=$ORIGPATH

