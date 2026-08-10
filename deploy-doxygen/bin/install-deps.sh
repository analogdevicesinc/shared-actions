#!/bin/bash

# Copyright 2026 Analog Devices, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -e

DEPS_DIR=${WORK_DIR}/deps

# Install and download dependencies
DOXYGEN_URL="https://sourceforge.net/projects/doxygen/files/rel-${VERSION}/doxygen-${VERSION}.src.tar.gz"

sudo apt-get install -y build-essential cmake graphviz python3-pip flex bison

mkdir -p ${DEPS_DIR}/doxygen
cd ${DEPS_DIR}

# Download doxygen 
wget --no-check-certificate --quiet ${DOXYGEN_URL} > /dev/null
tar --strip-components=1 -xvf doxygen-${VERSION}.src.tar.gz -C doxygen

# Installdoxygen tool
cd doxygen
mkdir -p build && cd build
cmake ..
make
sudo make install
