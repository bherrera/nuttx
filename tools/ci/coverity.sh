#!/bin/bash
# coverity.sh
#
#   Copyright (C) 2017 Bruno Herrera. All rights reserved.
#   Author: Bruno Herrera <bruherrera@gmail.com>
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in
#    the documentation and/or other materials provided with the
#    distribution.
# 3. Neither the name NuttX nor the names of its contributors may be
#    used to endorse or promote products derived from this software
#    without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
# FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
# COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
# INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
# BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS
# OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED
# AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
# ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
#

set -e

WD=`test -d ${0%/*} && cd ${0%/*}; pwd`
TOPDIR="${WD}/../.."

# Only run this on our branches
echo "Branch: $TRAVIS_BRANCH  |  Pull request: $TRAVIS_PULL_REQUEST  |  Slug: $TRAVIS_REPO_SLUG"
if [ "$TRAVIS_BRANCH" != "travis" -o "$TRAVIS_PULL_REQUEST" != "false" ];
then
  echo "Only analyzing the 'travis' brach of the main repository."
  exit 0
fi

# Environment check
[ -z "$COVERITY_SCAN_TOKEN" ] && echo "Need to set a coverity token" && exit 1

case $(uname -m) in
  i?86)       BITS=32 ;;
  amd64|x86_64) BITS=64 ;;
esac
SCAN_TOOL=https://scan.coverity.com/download/cxx/linux${BITS}
TOOL_BASE=$(pwd)/_coverity-scan

# Install coverity tools
if [ ! -d "$TOOL_BASE" ]; then
  echo "Downloading coverity..."
  mkdir -p "$TOOL_BASE"
  pushd "$TOOL_BASE"
  wget -O coverity_tool.tgz $SCAN_TOOL \
    --post-data "project=bherrera%2Fnuttx&token=$COVERITY_SCAN_TOKEN"
  tar xzf coverity_tool.tgz
  popd
  TOOL_DIR=$(find "$TOOL_BASE" -type d -name 'cov-analysis*')
  ln -s "$TOOL_DIR" "$TOOL_BASE"/cov-analysis
fi

#cp script/user_nodefs.h "$TOOL_BASE"/cov-analysis/config/user_nodefs.h

COV_BUILD="$TOOL_BASE/cov-analysis/bin/cov-build"
COV_CONFIGURE="$TOOL_BASE/cov-analysis/bin/cov-configure"

$COV_CONFIGURE --comptype gcc --compiler arm-none-eabi-gcc --template

# Compile
cd ${TOPDIR}
make distclean 1>/dev/null 2>&1
pushd tools
./configure.sh -l $1
popd
$COV_BUILD --dir cov-int make -j`$(nproc)`

# Upload results
tar czf nuttx.tgz cov-int
SHA=$(git rev-parse --short HEAD)

HTML="$(curl \
  --silent \
  --write-out "\n%{http_code}" \
  --form token="$COVERITY_SCAN_TOKEN" \
  --form email=bruherrera@gmail.com \
  --form file=@nuttx.tgz \
  --form version="$SHA" \
  --form description="Travis build" \
  https://scan.coverity.com/builds?project=bherrera%2Fnuttx)"
# Body is everything up to the last line
BODY="$(echo "$HTML" | head -n-1)"
# Status code is the last line
STATUS_CODE="$(echo "$HTML" | tail -n1)"

echo "${BODY}"

if [ "${STATUS_CODE}" != "201" ]; then
  echo "Received error code ${STATUS_CODE} from Coverity"
  exit 1
fi
