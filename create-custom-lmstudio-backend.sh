#!/bin/bash
#
# Create a custom LM Studio backend by copying official backend and replacing libraries
# This is the recommended approach since the .node bindings are proprietary
#

set -e

# Configuration
CUSTOM_SUFFIX="9"
SOURCE_BACKEND="llama.cpp-linux-x86_64-vulkan-avx2-2.10.0"
TARGET_BACKEND="llama.cpp-linux-x86_64-vulkan-avx2-2.10.${CUSTOM_SUFFIX}"
LMSTUDIO_BACKENDS_DIR="${HOME}/.lmstudio/extensions/backends"
SOURCE_DIR="${LMSTUDIO_BACKENDS_DIR}/${SOURCE_BACKEND}"
TARGET_DIR="${LMSTUDIO_BACKENDS_DIR}/${TARGET_BACKEND}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== LM Studio Custom Backend Creator ===${NC}"
echo ""

# Check if source backend exists
if [ ! -d "${SOURCE_DIR}" ]; then
    echo -e "${RED}Error: Source backend not found: ${SOURCE_DIR}${NC}"
    echo "Make sure LM Studio has downloaded the official Vulkan backend first."
    exit 1
fi

# Check if llama.cpp is built for LM Studio
LMSTUDIO_BUILD_DIR="build-lmstudio"
if [ ! -f "${LMSTUDIO_BUILD_DIR}/bin/libllama.so" ]; then
    echo -e "${YELLOW}llama.cpp libraries not found in ${LMSTUDIO_BUILD_DIR}. Building now...${NC}"
    
    mkdir -p ${LMSTUDIO_BUILD_DIR}
    cd ${LMSTUDIO_BUILD_DIR}
    
    cmake .. \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=ON \
        -DGGML_VULKAN=ON \
        -DGGML_NATIVE=OFF \
        -DGGML_AVX2=ON \
        -DLLAMA_BUILD_COMMON=ON \
        -DLLAMA_BUILD_EXAMPLES=OFF \
        -DLLAMA_BUILD_TESTS=OFF \
        -DLLAMA_BUILD_TOOLS=OFF \
        -DLLAMA_BUILD_SERVER=OFF
    
    make -j$(nproc) llama ggml ggml-base ggml-cpu ggml-vulkan
    
    cd ..
fi

echo -e "${GREEN}Source backend:${NC} ${SOURCE_BACKEND}"
echo -e "${GREEN}Target backend:${NC} ${TARGET_BACKEND}"
echo ""

# Step 1: Copy the official backend
echo -e "${BLUE}Step 1: Copying official backend...${NC}"
if [ -d "${TARGET_DIR}" ]; then
    echo -e "${YELLOW}Target directory exists. Removing...${NC}"
    rm -rf "${TARGET_DIR}"
fi
cp -r "${SOURCE_DIR}" "${TARGET_DIR}"
echo -e "${GREEN}✓ Copied to ${TARGET_DIR}${NC}"

# Step 2: Replace libraries with custom-built ones
echo -e "${BLUE}Step 2: Replacing libraries with custom build...${NC}"

# Function to safely replace library
replace_lib() {
    local libname=$1
    local source_path="${LMSTUDIO_BUILD_DIR}/bin/${libname}"
    local target_path="${TARGET_DIR}/${libname}"
    
    if [ -L "${source_path}" ]; then
        # It's a symlink, resolve it
        local real_lib=$(readlink -f "${source_path}")
        local real_name=$(basename "${real_lib}")
        
        # Copy both the real library and create the symlink
        cp "${real_lib}" "${TARGET_DIR}/${real_name}"
        ln -sf "${real_name}" "${target_path}"
        
        # Also copy versioned library if it exists
        if [ -f "${real_lib}.0" ]; then
            cp "${real_lib}.0" "${TARGET_DIR}/${real_name}.0"
        fi
        
        echo -e "  ${GREEN}✓${NC} ${libname} -> ${real_name}"
    elif [ -f "${source_path}" ]; then
        cp "${source_path}" "${target_path}"
        echo -e "  ${GREEN}✓${NC} ${libname}"
    else
        echo -e "  ${YELLOW}⚠${NC} ${libname} not found in build"
    fi
}

# Replace core libraries
replace_lib "libllama.so"
replace_lib "libggml.so"
replace_lib "libggml-base.so"
replace_lib "libggml-cpu.so"
replace_lib "libggml-vulkan.so"



# Copy ggml_llamacpp if it exists
if [ -f "${LMSTUDIO_BUILD_DIR}/bin/libggml_llamacpp.so" ]; then
    replace_lib "libggml_llamacpp.so"
fi

echo ""

# Step 3: Update backend-manifest.json
echo -e "${BLUE}Step 3: Updating backend-manifest.json...${NC}"

MANIFEST="${TARGET_DIR}/backend-manifest.json"

# Use jq if available, otherwise use sed
if command -v jq >/dev/null 2>&1; then
    jq --arg name "llama.cpp-linux-x86_64-vulkan-avx2-${CUSTOM_SUFFIX}" \
       --arg version "2.10.${CUSTOM_SUFFIX}" \
       '.name = $name | .version = $version' \
       "${MANIFEST}" > "${MANIFEST}.tmp" && mv "${MANIFEST}.tmp" "${MANIFEST}"
else
    # Fallback to sed
    sed -i "s/\"version\": \"[^\"]*\"/\"version\": \"2.10.${CUSTOM_SUFFIX}\"/" "${MANIFEST}"
    sed -i "s/\"name\": \"[^\"]*\"/\"name\": \"llama.cpp-linux-x86_64-vulkan-avx2-${CUSTOM_SUFFIX}\"/" "${MANIFEST}"
fi

echo -e "${GREEN}✓ Updated version to 2.10.${CUSTOM_SUFFIX}${NC}"
echo -e "${GREEN}✓ Updated name to llama.cpp-linux-x86_64-vulkan-avx2-${CUSTOM_SUFFIX}${NC}"

# Step 4: Update display-data.json
echo -e "${BLUE}Step 4: Updating display-data.json...${NC}"

DISPLAY_DATA="${TARGET_DIR}/display-data.json"
if [ -f "${DISPLAY_DATA}" ]; then
    # Create updated display data
    cat > "${DISPLAY_DATA}" << EOF
[["en",{"langKey":"en","displayName":"Vulkan llama.cpp (Linux) - ${CUSTOM_SUFFIX}","description":"Custom Vulkan accelerated llama.cpp engine (${CUSTOM_SUFFIX} build)","releaseNotes":[{"version":"2.10.${CUSTOM_SUFFIX}","releaseNotes":"- Custom build with 2.10.${CUSTOM_SUFFIX} modifications\n- Based on llama.cpp b8429\n"}]}]]
EOF
    echo -e "${GREEN}✓ Updated display name to 'Vulkan llama.cpp (Linux) - 2.10.${CUSTOM_SUFFIX}'${NC}"
fi

# Step 5: Set permissions
echo -e "${BLUE}Step 5: Setting permissions...${NC}"
chmod +x "${TARGET_DIR}"/*.node
chmod +x "${TARGET_DIR}"/*.so*

# Step 6: Verify the backend
echo -e "${BLUE}Step 6: Verifying backend...${NC}"

# Check for missing dependencies
echo "Checking library dependencies..."
MISSING_DEPS=$(ldd "${TARGET_DIR}/llm_engine_vulkan.node" 2>/dev/null | grep "not found" || true)
if [ -n "${MISSING_DEPS}" ]; then
    echo -e "${YELLOW}Warning: Missing dependencies found:${NC}"
    echo "${MISSING_DEPS}"
else
    echo -e "${GREEN}✓ All dependencies resolved${NC}"
fi

echo ""
echo -e "${GREEN}=== Custom Backend Created Successfully! ===${NC}"
echo ""
echo -e "Location: ${BLUE}${TARGET_DIR}${NC}"
echo ""
echo "To use this backend:"
echo "1. Restart LM Studio"
echo "2. Go to Settings > AI Runtime > Local Engine"
echo "3. Select '2.10.${CUSTOM_SUFFIX}' variant from the backend dropdown"
echo ""
echo "To verify the libraries:"
echo "  ls -la ${TARGET_DIR}"
echo ""
echo "To debug issues:"
echo "  LD_LIBRARY_PATH=${TARGET_DIR} ldd ${TARGET_DIR}/llm_engine_vulkan.node"
echo ""

# List the final contents
echo -e "${BLUE}Backend contents:${NC}"
ls -la "${TARGET_DIR}"
