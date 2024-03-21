#!/bin/bash
# Be verbose
#set -x

# Exit on failure
set -e

if [ -z ${BUILD_DONE_DIR} ]; then
    echo !!! This script must only be called from buildTAK.sh !!!
    exit 1
fi

DONE_EXTRACT_LIBRARIES=${BUILD_DONE_DIR}/prebuild.01.extract-libraries
DONE_RESET_CONAN=${BUILD_DONE_DIR}/prebuild.02.reset-conan
DONE_BUILD_LIB_=${BUILD_DONE_DIR}/prebuild.3.build-lib
DONE_PUBLISH_LIBS=${BUILD_DONE_DIR}/prebuild.4.publish-libs
DONE_INSTALL_TTP=${BUILD_DONE_DIR}/prebuild.5.install-ttp
DONE_PUBLISH_TINYGLTF=${BUILD_DONE_DIR}/prebuild.6.publish-tinygltf
DONE_BUILD_LASZIP_=${BUILD_DONE_DIR}/prebuild.7.build-laszip
DONE_PUBLISH_LASZIP=${BUILD_DONE_DIR}/prebuild.8.publish-laszip
DONE_BUILD_LIBLAS_=${BUILD_DONE_DIR}/prebuild.9.build-liblas
DONE_PUBLISH_LIBLAS=${BUILD_DONE_DIR}/prebuild.10.publish-liblas
DONE_PUBLISH_STL_SOFT=${BUILD_DONE_DIR}/prebuild.11.publish-stl-soft
DONE_PUBLISH_KHRONOS=${BUILD_DONE_DIR}/prebuild.12.publish-khronos

# The rest of the script requires that we're in the script directory
pushd $(dirname $(readlink -f $0))

if [ ! -d ../takengine/thirdparty ]; then
    mkdir -p ../takengine/thirdparty
fi

if [ ! -f ${DONE_EXTRACT_LIBRARIES} ]; then
    echo Extracting third-party libraries...

    # Extract everything in parallel
    tar zxf ../depends/assimp-4.0.1-mod.tar.gz         -C ../ &
    tar zxf ../depends/gdal-2.4.4-mod.tar.gz           -C ../ &
    tar zxf ../depends/tinygltf-2.4.1-mod.tar.gz       -C ../takengine/thirdparty &
    tar zxf ../depends/tinygltfloader-0.9.5-mod.tar.gz -C ../takengine/thirdparty &
    tar zxf ../depends/libLAS-1.8.2-mod.tar.gz         -C ../ &
    tar zxf ../depends/LASzip-3.4.3-mod.tar.gz         -C ../ &
    wait
    
    touch ${DONE_EXTRACT_LIBRARIES}
fi

if [ ! -f ${DONE_RESET_CONAN} ]; then
    if [ -d ~/.conan ]; then
        find ~/.conan -mindepth 1 -delete
    else
        rm -rf ~/.conan
    fi
    conan profile new default --detect
    # This step is required to ensure conan package IDs are consistent between prebuild and build steps
    conan profile update settings.compiler.version=8 default

    touch ${DONE_RESET_CONAN}
fi

# Update java source/target to 1.8 in java build files
sed -i 's#="1.6"#="1.8"#g' ../gdal/swig/java/build.xml
sed -i 's#="1.6"#="1.8"#g' ../assimp/port/jassimp/build.xml

# Anything other than 1 here seems to cause issues with the build
NUMCPUS=1
TARGETS="android-armeabi-v7a android-arm64-v8a android-x86"
BUILDS="build_spatialite build_commoncommo build_gdal build_assimp"
for TARGET in ${TARGETS};
do
	(
		for BUILD in ${BUILDS};
		do
			(
                if [ ! -f ${DONE_BUILD_LIB_}-${BUILD}-${TARGET} ]; then
                    printf "*************************************************\n"
                    printf "BUILDING TARGET: ${TARGET} for ${BUILD}\n"
                    printf "make -j ${NUMCPUS} -C ../takthirdparty TARGET=${TARGET} GDAL_USE_KDU=no ${BUILD}\n"
                    printf "*************************************************\n"
                    make -j ${NUMCPUS} -C ../takthirdparty TARGET=${TARGET} GDAL_USE_KDU=no ${BUILD}
                    
                    touch ${DONE_BUILD_LIB_}-${BUILD}-${TARGET}
                fi
			)
		done
	)
done

pushd ../takthirdparty

# Add links to builds to the root
ln -sf builds/android-armeabi-v7a-release android-armeabi-v7a-release
ln -sf builds/android-arm64-v8a-release android-arm64-v8a-release
ln -sf builds/android-x86-release android-x86-release

cd ci-support
# install the packages locally

if [ ! -f ${DONE_PUBLISH_LIBS} ]; then
    # conan
    conan export-pkg . -s arch=armv8 -s os=Android -s os.api_level=29 -f
    conan export-pkg . -s arch=armv7 -s os=Android -s os.api_level=29 -f
    conan export-pkg . -s arch=x86   -s os=Android -s os.api_level=29 -f
    
    touch ${DONE_PUBLISH_LIBS}
fi

if [ ! -f ${DONE_INSTALL_TTP} ]; then
    # Install TTP maven package
    ./gradlew assemble
    ./gradlew publishTtpRuntimeAndroidPublicationToMavenLocal
    
    touch ${DONE_INSTALL_TTP}
fi

# return to "scripts"
popd

if [ ! -f ${DONE_PUBLISH_TINYGLTF} ]; then
    pushd ../takengine/thirdparty/tinygltf

    # install tinygltf conan packages
    conan export-pkg . -f
    # install tinygltf conan packages
    cd ../tinygltfloader
    conan export-pkg . -f

    # return to "scripts"
    popd
    
    touch ${DONE_PUBLISH_TINYGLTF}
fi

# build and install LASzip package
pushd ../LASzip
ANDROID_ABIS="arm64-v8a armeabi-v7a x86"
for LASZIP_ANDROID_ABI in ${ANDROID_ABIS} ;
do
	(
        if [ ! -f ${DONE_BUILD_LASZIP_}-${LASZIP_ANDROID_ABI} ]; then
            rm -rf build-android-${LASZIP_ANDROID_ABI}
            mkdir -p build-android-${LASZIP_ANDROID_ABI}
            cd build-android-${LASZIP_ANDROID_ABI}
            cmake .. \
                -G Ninja \
                -DCMAKE_TOOLCHAIN_FILE=../cmake/android.toolchain.cmake \
                -DCMAKE_BUILD_TYPE=Release \
                -DANDROID_NDK=${ANDROID_NDK_HOME} \
                -DANDROID_ABI=${LASZIP_ANDROID_ABI} \
                -DANDROID_TOOLCHAIN=gcc \
                -DANDROID_STL=gnustl_static \
                -DANDROID_PLATFORM=android-24 \
                -DCMAKE_CXX_FLAGS="-fexceptions -frtti -std=c++11" \
                -DLASZIP_BUILD_STATIC=ON
            cmake --build .
            cp -r ../include .
            cp ../src/*.hpp ./include/laszip

            touch ${DONE_BUILD_LASZIP_}-${LASZIP_ANDROID_ABI}
        fi
	)&
done
wait

if [ ! -f ${DONE_PUBLISH_LASZIP} ]; then
    cd ci-support
    conan export-pkg . -s arch=armv8 -s os=Android -s os.api_level=29 -s compiler.version="8" -f
    conan export-pkg . -s arch=armv7 -s os=Android -s os.api_level=29 -s compiler.version="8" -f
    conan export-pkg . -s arch=x86   -s os=Android -s os.api_level=29 -s compiler.version="8" -f
    
    touch ${DONE_PUBLISH_LASZIP}
fi

# return to "scripts"
popd

# build and install libLAS package
pushd ../libLAS
ANDROID_ABIS="arm64-v8a armeabi-v7a x86"
for LIBLAS_ANDROID_ABI in ${ANDROID_ABIS} ;
do
	(
        if [ ! -f ${DONE_BUILD_LIBLAS_}-${LIBLAS_ANDROID_ABI} ]; then
            rm -rf build-android-${LIBLAS_ANDROID_ABI}
            mkdir -p build-android-${LIBLAS_ANDROID_ABI}
            cd build-android-${LIBLAS_ANDROID_ABI}
            cmake .. \
                -G Ninja \
                -DCMAKE_TOOLCHAIN_FILE=../cmake/android.toolchain.cmake \
                -DCMAKE_BUILD_TYPE=Release \
                -DANDROID_NDK=${ANDROID_NDK_HOME} \
                -DANDROID_ABI=${LIBLAS_ANDROID_ABI} \
                -DANDROID_TOOLCHAIN=gcc \
                -DANDROID_STL=gnustl_static \
                -DANDROID_PLATFORM=android-24 \
                -DCMAKE_CXX_FLAGS="-fexceptions -frtti -std=c++11" \
                -DLASZIP_BUILD_STATIC=ON
            cmake --build . --target las_c
            cmake --build . --target las
            cp -r ../include .
            
            touch ${DONE_BUILD_LIBLAS_}-${LIBLAS_ANDROID_ABI}
        fi
	)&
done
wait

if [ ! -f ${DONE_PUBLISH_LIBLAS} ]; then
    cd ci-support

    # publish to conan
    conan export-pkg . -s arch=armv8 -s os=Android -s os.api_level=29 -s compiler.version="8" -f
    conan export-pkg . -s arch=armv7 -s os=Android -s os.api_level=29 -s compiler.version="8" -f
    conan export-pkg . -s arch=x86   -s os=Android -s os.api_level=29 -s compiler.version="8" -f

    # publish to maven
    ./gradlew assemble
    ./gradlew publishLibLasAndroidPublicationToMavenLocal
    
    touch ${DONE_PUBLISH_LIBLAS}
fi

# return to "scripts"
popd

if [ ! -f ${DONE_PUBLISH_STL_SOFT} ]; then
    cp stl-soft-conanfile.py ../stl-soft/conanfile.py
    pushd ../stl-soft
    conan export-pkg . -f
    popd

    touch ${DONE_PUBLISH_STL_SOFT}
fi

if [ ! -f ${DONE_PUBLISH_KHRONOS} ]; then
    cp khronos-conanfile.py ../khronos/conanfile.py
    pushd ../khronos
    conan export-pkg . -f
    popd
    
    touch ${DONE_PUBLISH_KHRONOS}
fi

# return to calling directory
popd
