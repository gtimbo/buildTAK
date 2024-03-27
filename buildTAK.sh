#!/bin/bash
# Verbose output
#set -x

# Stop on Error
set -e

# Certificate/key variables
CERTIFICATE_DISTINGUISHED_NAME="CN=Unknown, OU=Unknown, O=Unknown, L=Unknown, ST=Unknown, C=AU"
KEY_STORE_PASSWORD="default"
KEY_PASSWORD="default"

# Variables for command line options
PREBUILD_ONLY=0
SKIP_DOWNLOADS=0
RESET_BUILD=0
DELETE_ALL=0

usage() {
cat << EOF
Usage: $0 [-hsprd] <build directory>
  -h    Display help
  -s    Skip downloading Android SDK files
  -p    Run the pre-build script to compile third-party libraries, but do not build ATAK
  -r    Perform a complete rebuild (i.e. reset any previous build progress)
  -d    Delete the build directory and all downloaded files
EOF
}

while getopts "hsprd" option;
do
    case "${option}" in
        h)
            usage
            exit 0
            ;;
        s)
            SKIP_DOWNLOADS=1
            ;;
        p)
            PREBUILD_ONLY=1
            ;;
        r)
            RESET_BUILD=1
            ;;
        d)
            DELETE_ALL=1
            ;;
        ?)
            usage
            exit 1
            ;;
    esac
done
shift $((OPTIND-1))

# Capture the build directory, removing any trailing '/' character
BUILD_DIR_ARG=${1%/}

if [ -z ${BUILD_DIR_ARG} ]; then
    echo "Missing build directory!"
    echo
    usage
    exit 1
fi

PWD=`pwd`
BASE_BUILD_DIR=${PWD}/${BUILD_DIR_ARG}
ATAK_BUILD_DIR=${BASE_BUILD_DIR}/atak

# URLS used to download files
ANDROID_REPOSITORY_URL=https://dl.google.com/android/repository
CMAKE_URL=https://cmake.org/files/v3.14

# Files to download
NDK_FILE=android-ndk-r12b-linux-x86_64.zip
CMDLINE_TOOLS_FILE=commandlinetools-linux-8512546_latest.zip
CMAKE_FILE=cmake-3.14.7-Linux-x86_64.tar.gz

# Directories for the Android SDK and related tools
ANDROID_SDK_ROOT=${PWD}/android-sdk
BASE_NDK_DIR=${ANDROID_SDK_ROOT}/ndk
ANDROID_NDK_HOME=${BASE_NDK_DIR}/android-ndk-r12b
CMDLINE_TOOLS_DIR=${ANDROID_SDK_ROOT}/cmdline-tools
CMAKE_DIR=${ANDROID_SDK_ROOT}/cmake-3.14.7-Linux-x86_64

# Files and directories used internally by the script
DOWNLOAD_DIR=${PWD}/.download
GLOBAL_DONE_DIR=${PWD}/.done
BUILD_DONE_DIR=${BASE_BUILD_DIR}/.done

DONE_INSTALL_REQUIRED_TOOLS=${GLOBAL_DONE_DIR}/01.install-pre-requisites
DONE_EXTRACT_NDK=${GLOBAL_DONE_DIR}/02.extract-ndk
DONE_EXTRACT_CMAKE=${GLOBAL_DONE_DIR}/03.extract-cmake
DONE_EXTRACT_CMDLINE_TOOLS=${GLOBAL_DONE_DIR}/04.extract-cmdline-tools
DONE_DOWNLOAD_ANDROID_SDK=${GLOBAL_DONE_DIR}/05.download-android-sdk

DONE_CLONE_ATAK_REPOSITORY=${BUILD_DONE_DIR}/01.clone-atak-repository
DONE_PREBUILD=${BUILD_DONE_DIR}/02.prebuild
DONE_GENERATE_KEYS=${BUILD_DONE_DIR}/03.generate-keys
DONE_UPDATE_LOCAL_PROPERTIES=${BUILD_DONE_DIR}/04.update-local-properties
DONE_BUILD_CIV_RELEASE=${BUILD_DONE_DIR}/05.build-civ-release

PATH=${PATH}:${CMAKE_DIR}/bin

export ANDROID_SDK_ROOT
export ANDROID_NDK_HOME
export ANDROID_NDK=${ANDROID_NDK_HOME}
export JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk-amd64
export BUILD_DONE_DIR

# Download a file to the download directory.
#
# $1 = base URL
# $2 = file name
download() {
    if [ ! -f ${DOWNLOAD_DIR}/${2} ]; then
        wget --timeout=60 --tries=0 -P ${DOWNLOAD_DIR} ${1}/${2}
    else
        wget --timeout=60 --tries=0 -c -P ${DOWNLOAD_DIR} ${1}/${2}
    fi
}

if [ ${DELETE_ALL} == 1 ]; then
    echo Deleting global progress...
    rm -rf ${GLOBAL_DONE_DIR}
    echo Deleting downloaded files...
    rm -rf ${DOWNLOAD_DIR}
    echo Deleting Android SDK...
    rm -rf ${ANDROID_SDK_ROOT}
    echo Deleting ATAK build directory...
    rm -rf ${BASE_BUILD_DIR}

    exit 0
fi

if [ ! -d ${DOWNLOAD} ]; then
    mkdir ${DOWNLOAD}
fi
if [ ! -d ${GLOBAL_DONE_DIR} ]; then
    mkdir ${GLOBAL_DONE_DIR}
fi

if [ ! -f ${DONE_INSTALL_REQUIRED_TOOLS} ]; then
    # Install the tools required to build the system
    sudo apt -y install git git-lfs python3-pip dos2unix cmake build-essential tcl ninja-build libxml2-dev \
    libssl-dev sqlite3 zlib1g-dev ant openjdk-8-jdk automake autoconf libtool swig cmake apg g++ \
    make tcl patch libogdi-dev

    pip3 install conan==1.60.2

    touch ${DONE_INSTALL_REQUIRED_TOOLS}
fi

# Download files
if [ ${SKIP_DOWNLOADS} == 0 ]; then
    download ${ANDROID_REPOSITORY_URL} ${NDK_FILE}
    download ${ANDROID_REPOSITORY_URL} ${CMDLINE_TOOLS_FILE}
    download ${CMAKE_URL} ${CMAKE_FILE}
fi

if [ ! -f ${DONE_EXTRACT_NDK} ]; then
    echo Extracting NDK...

    if [ -d ${ANDROID_NDK_HOME} ]; then
        rm -rf ${ANDROID_NDK_HOME}
    fi

    mkdir -p ${ANDROID_NDK_HOME}
    unzip -q ${DOWNLOAD_DIR}/${NDK_FILE} -d ${BASE_NDK_DIR}

    touch ${DONE_EXTRACT_NDK}
fi

if [ ! -f ${DONE_EXTRACT_CMAKE} ]; then
    echo Extracting CMAKE...

    if [ -d ${CMAKE_DIR} ]; then
        rm -rf ${CMAKE_DIR}
    fi

    mkdir -p ${CMAKE_DIR}
    tar zxf ${DOWNLOAD_DIR}/${CMAKE_FILE} -C ${ANDROID_SDK_ROOT}

    touch ${DONE_EXTRACT_CMAKE}
fi

if [ ! -f ${DONE_EXTRACT_CMDLINE_TOOLS} ]; then
    echo Extracting COMMANDLINE TOOLS...

    if [ -d ${CMDLINE_TOOLS_DIR} ]; then
        rm -rf ${CMDLINE_TOOLS_DIR}
    fi

    unzip -q ${DOWNLOAD_DIR}/${CMDLINE_TOOLS_FILE} -d ${ANDROID_SDK_ROOT}

    touch ${DONE_EXTRACT_CMDLINE_TOOLS}
fi

if [ ! -f ${DONE_DOWNLOAD_ANDROID_SDK} ]; then
    echo Downloading Android SDK...
    echo "y" | ${CMDLINE_TOOLS_DIR}/bin/sdkmanager --sdk_root=${ANDROID_SDK_ROOT} --licenses
    echo "y" | ${CMDLINE_TOOLS_DIR}/bin/sdkmanager --sdk_root=${ANDROID_SDK_ROOT} --install "platforms;android-29"

    touch ${DONE_DOWNLOAD_ANDROID_SDK}
fi

if [ ! -d ${BASE_BUILD_DIR} ]; then
    mkdir -p ${BASE_BUILD_DIR}
fi

if [ ! -f ${DONE_CLONE_ATAK_REPOSITORY} ]; then
    git clone https://github.com/deptofdefense/AndroidTacticalAssaultKit-CIV.git ${BASE_BUILD_DIR}

    pushd ${BASE_BUILD_DIR}

    git lfs install --local
    git lfs fetch
    git lfs checkout

    git submodule update --init --recursive

    popd

    mkdir -p ${BUILD_DONE_DIR}
    touch ${DONE_CLONE_ATAK_REPOSITORY}
fi

pushd ${BASE_BUILD_DIR}

# If the user requests it, reset the build by deleting the third-party libraries and cleaning the gradle build
if [ ${RESET_BUILD} == 1 ]; then
    pushd atak
    ./gradlew clean;
    popd

    rm -rf assimp gdal takengine/thirdparty libLAS LASzip

    rm ${DONE_PREBUILD}
    rm ${BUILD_DONE_DIR}/prebuild*
fi

if [ ! -f ${DONE_PREBUILD} ]; then
    cp ../prebuildTAK.sh scripts
    pushd scripts
    ./prebuildTAK.sh
    popd

    touch ${DONE_PREBUILD}

    # We can now exit if the user only wanted to do the pre-build
    if [ ${PREBUILD_ONLY} == 1 ]; then
        echo
        echo Exiting as only running the pre-build was requested
        exit 0
    fi
fi

pushd ${ATAK_BUILD_DIR}

KEYFILE="${ATAK_BUILD_DIR}/${BUILD_DIR_ARG}.keystore"

if [ ! -f ${DONE_GENERATE_KEYS} ]; then

    if [ -f ${KEYFILE} ]; then
        rm -f ${KEYFILE}
    fi

    keytool -keystore ${KEYFILE} -genkey -validity 10000 -keyalg RSA -alias debug -dname "${CERTIFICATE_DISTINGUISHED_NAME}" -storepass "${KEY_STORE_PASSWORD}" -keypass "${KEY_PASSWORD}"
    keytool -keystore ${KEYFILE} -genkey -validity 10000 -keyalg RSA -alias release -dname "${CERTIFICATE_DISTINGUISHED_NAME}" -storepass "${KEY_STORE_PASSWORD}" -keypass "${KEY_PASSWORD}"

    if [ ! -f android_keystore ]; then
        ln -s ${KEYFILE} android_keystore
    fi

    touch ${DONE_GENERATE_KEYS}
fi

if [ ! -f ${DONE_UPDATE_LOCAL_PROPERTIES} ]; then
cat > local.properties << EOL
ndk.dir={NDKDIR}
sdk.dir={SDKDIR}
cmake.dir={CMAKEDIR}

takDebugKeyFile={KEYFILE}
takDebugKeyFilePassword={STOREPASSWORD}
takDebugKeyAlias=debug
takDebugKeyPassword={KEYPASSWORD}
takReleaseKeyFile={KEYFILE}
takReleaseKeyFilePassword={STOREPASSWORD}
takReleaseKeyAlias=release
takReleaseKeyPassword={KEYPASSWORD}
EOL

    sed -i "s#{NDKDIR}#${ANDROID_NDK_HOME}#g" local.properties
    sed -i "s#{SDKDIR}#${ANDROID_SDK_ROOT}#g" local.properties
    sed -i "s#{CMAKEDIR}#${CMAKE_DIR}#g" local.properties
    sed -i "s#{KEYFILE}#${KEYFILE}#g" local.properties
    sed -i "s/{KEYPASSWORD}/${KEY_PASSWORD}/g" local.properties
    sed -i "s/{STOREPASSWORD}/${KEY_STORE_PASSWORD}/g" local.properties

    touch ${DONE_UPDATE_LOCAL_PROPERTIES}
fi

if [ ! -f ${DONE_BUILD_CIV_RELEASE} ]; then
    export takRepoConanUrl=
    export takRepoUsername=
    export takRepoPassword=

cat > build.gradle << EOL
buildscript {
    repositories {
        jcenter()
        google()
    }

    dependencies {
        classpath "com.android.tools.build:gradle:4.2.2"
    }
}
EOL

    # Do NOT stop on Error, as we expect the first build to fail
    set +e

    ./gradlew generateJniHeaders assembleCivRelease

    #
    # The build will fail the first time looking for the Khronos library, so re-export it to conan,
    # which seems to fix the problem.
    #
    pushd ../scripts

    cp khronos-conanfile.py ../khronos/conanfile.py
    pushd ../khronos
    conan export-pkg . -f
    popd

    popd

    # Now stop on Error, as if this fails we want to know about it
    set -e

    ./gradlew assembleCivRelease

    touch ${DONE_BUILD_CIV_RELEASE}
fi

popd
popd

