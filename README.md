# buildTAK
The `buildTAK.sh` script builds ATAK 4.6.0.5 from source from a completely blank slate; it **does not** assume that any required tools or dependencies have been installed.

The script:
1. installs all of the required linux tools
1. downloads all of the required Android dependencies
1. clones the ATAK repository
1. builds all of the third-party libraries
1. builds ATAK

If all is successful, you should have both debug and release versions of ATAK.

## Progressive Building
Building ATAK from scratch usually takes multiple hours. Therefore, the script records its progress so that if the build fails at any stage, or if you need to stop the script for any reason, re-running it will skip any steps that have already been successfully completed.

The progress is recorded in two `.done` directories: one in the directory containing this script; and one in the build directory supplied as an argument to the script.

To repeat any step, simply delete the corresponding file in the appropriate `.done` directory before re-running the script.

## Install and Run
1. Clone this repo into a new directory, and then change to that directory.
1. If desired, edit the variables at the top of `buildTAK.sh` that define the certificate distinguished name and key/keystore passwords.
1. Execute the `buildTAK.sh` script, providing as an argument a directory in which to clone and build ATAK (e.g. `./buildTAK.sh MyTAK`).
1. The script will download and configure all of the required tools and libraries, then build both debug and release versions of ATAK 4.6.0.5.

Note that running `buildTAK.sh` from any directory other than the cloned repository directory is not currently supported.

## Script Options
Run the script from the directory into which you cloned this repository.

```
Usage: ./buildTAK.sh [-hsprd] <build directory>
  -h    Display help
  -s    Skip downloading Android SDK files
  -p    Run the pre-build script to compile third-party libraries, but do not build ATAK
  -r    Perform a complete rebuild (i.e. reset any previous build progress)
  -d    Delete the build directory and all downloaded files
```
