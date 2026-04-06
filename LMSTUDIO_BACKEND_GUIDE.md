# LM Studio Backend Extension Guide for llama.cpp

This guide explains how to create node-gyp bindings that make llama.cpp available as an LM Studio backend extension.

## Overview

LM Studio uses Node-API (N-API) native addons (`.node` files) to interface with inference backends. To create a custom backend at:

```
/home/mk/.lmstudio/extensions/backends/llama.cpp-linux-x86_64-vulkan-avx2-2.10.0-qades
```

You need to:
1. Build llama.cpp as shared libraries
2. Create Node.js native addons that wrap llama.cpp APIs
3. Create proper metadata files (backend-manifest.json)

## Important Note

**The LM Studio Node.js bindings are proprietary to Element Labs (LM Studio's creators).** The examples provided here show the structure and approach, but the actual LM Studio integration APIs are not publicly documented. This guide helps you understand the technical approach, but you'll need to reverse-engineer or obtain the actual LM Studio SDK for full compatibility.

## Prerequisites

```bash
# Install Node.js (18+ recommended)
# Install build tools
sudo apt-get install build-essential cmake git

# Install Vulkan SDK (for GPU acceleration)
# Follow: https://vulkan.lunarg.com/doc/view/latest/linux/getting_started.html

# Install node-gyp globally
npm install -g node-gyp

# Install node-addon-api
npm install node-addon-api
```

## Project Structure

```
llama.cpp/
├── binding.gyp                    # node-gyp build configuration
├── package.json                   # npm package configuration
├── backend-manifest.json          # LM Studio backend metadata
├── src/
│   └── node_bindings/            # Node.js binding source files
│       ├── llm_engine_wrapper.cpp
│       └── lmstudio_bindings.cpp
├── build/                         # Build output
└── build-lmstudio/               # llama.cpp CMake build
```

## Step-by-Step Build Instructions

### 1. Build llama.cpp Shared Libraries

```bash
mkdir -p build-lmstudio
cd build-lmstudio

cmake .. \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=ON \
    -DGGML_VULKAN=ON \
    -DGGML_AVX2=ON \
    -DLLAMA_BUILD_EXAMPLES=OFF \
    -DLLAMA_BUILD_TESTS=OFF

make -j$(nproc) llama ggml ggml-base ggml-cpu ggml-vulkan

cd ..
```

### 2. Set Up Node.js Project

```bash
# Create package.json
cat > package.json << 'EOF'
{
  "name": "llama.cpp-lmstudio-backend",
  "version": "2.10.0-qades",
  "gypfile": true,
  "scripts": {
    "build": "node-gyp rebuild"
  },
  "dependencies": {
    "node-addon-api": "^7.0.0"
  }
}
EOF

npm install
```

### 3. Create binding.gyp

```json
{
  "targets": [
    {
      "target_name": "llm_engine_vulkan",
      "sources": [ "src/node_bindings/llm_engine_wrapper.cpp" ],
      "include_dirs": [
        "<!@(node -p \"require('node-addon-api').include\")",
        "include",
        "ggml/include"
      ],
      "libraries": [
        "-L<(PRODUCT_DIR)/../../build-lmstudio/bin",
        "-lllama",
        "-lvulkan"
      ],
      "cflags_cc": [ "-std=c++17", "-mavx2" ],
      "defines": [ "NAPI_DISABLE_CPP_EXCEPTIONS" ]
    }
  ]
}
```

### 4. Build the Node.js Addons

```bash
npx node-gyp rebuild
```

### 5. Install to LM Studio

```bash
TARGET_DIR="${HOME}/.lmstudio/extensions/backends/llama.cpp-linux-x86_64-vulkan-avx2-2.10.0-qades"
mkdir -p "${TARGET_DIR}"

# Copy libraries
cp build-lmstudio/bin/*.so "${TARGET_DIR}/"

# Copy Node.js addons
cp build/Release/*.node "${TARGET_DIR}/"

# Copy manifest
cp backend-manifest.json "${TARGET_DIR}/"
```

## Key Files Explained

### backend-manifest.json

This is the entry point LM Studio uses to discover and load your backend:

```json
{
  "version": "2.10.0-qades",
  "domains": ["llm", "embedding"],
  "engine": "llama.cpp",
  "target_libraries": [
    {
      "name": "llm_engine_vulkan.node",
      "type": "llm_engine",
      "version": "0.1.0"
    }
  ],
  "platform": "linux",
  "cpu": {
    "architecture": "x86_64",
    "instruction_set_extensions": ["AVX2"]
  },
  "gpu": {
    "framework": "Vulkan"
  },
  "supported_model_formats": ["gguf"],
  "manifest_version": "4",
  "extension_type": "engine",
  "name": "llama.cpp-linux-x86_64-vulkan-avx2-qades"
}
```

### Node.js Native Addon

The `.node` files are essentially shared libraries that export Node-API functions. They must export an initialization function that LM Studio can call:

```cpp
#include <napi.h>

Napi::Object Init(Napi::Env env, Napi::Object exports) {
    // Register your classes and functions
    LLMEngineWrapper::Init(env, exports);
    return exports;
}

NODE_API_MODULE(llm_engine_vulkan, Init)
```

## Troubleshooting

### Issue: "Cannot find module" errors

Make sure all `.so` files are in the same directory as the `.node` files, or set `LD_LIBRARY_PATH`:

```bash
export LD_LIBRARY_PATH=/home/mk/.lmstudio/extensions/backends/llama.cpp-linux-x86_64-vulkan-avx2-2.10.0-qades:$LD_LIBRARY_PATH
```

### Issue: Symbol not found

The Node.js addon and llama.cpp libraries must be built with compatible compiler settings. Check with:

```bash
nm -D /path/to/library.so | grep symbol_name
```

### Issue: LM Studio doesn't show the backend

1. Verify `backend-manifest.json` is valid JSON
2. Check LM Studio's developer console for errors
3. Ensure the backend directory name matches the `name` field in manifest

## Using the Example Files

Example files are provided with `.example` suffixes:

```bash
# Copy examples to actual files
cp binding.gyp.example binding.gyp
cp package.json.example package.json
cp backend-manifest.json.example backend-manifest.json
mkdir -p src/node_bindings
cp src/node_bindings/llm_engine_wrapper.cpp.example src/node_bindings/llm_engine_wrapper.cpp

# Run the build script
chmod +x build-lmstudio-backend.sh
./build-lmstudio-backend.sh
```

## Alternative: Using Existing Backends

If you just want to use a custom build of llama.cpp with LM Studio, you can:

1. Copy an existing official backend as a template
2. Replace the `.so` files with your custom builds
3. Keep the `.node` binding files from the official release

```bash
# Copy existing backend
cp -r ~/.lmstudio/extensions/backends/llama.cpp-linux-x86_64-vulkan-avx2-2.10.0 \
      ~/.lmstudio/extensions/backends/llama.cpp-linux-x86_64-vulkan-avx2-2.10.0-custom

# Replace libraries with your build
cp build-lmstudio/bin/lib*.so \
   ~/.lmstudio/extensions/backends/llama.cpp-linux-x86_64-vulkan-avx2-2.10.0-custom/

# Update manifest
jq '.version = "2.10.0-custom" | .name = "llama.cpp-linux-x86_64-vulkan-avx2-custom"' \
   ~/.lmstudio/extensions/backends/llama.cpp-linux-x86_64-vulkan-avx2-2.10.0-custom/backend-manifest.json > \
   /tmp/manifest.json && mv /tmp/manifest.json \
   ~/.lmstudio/extensions/backends/llama.cpp-linux-x86_64-vulkan-avx2-2.10.0-custom/backend-manifest.json
```

## Resources

- [Node-API documentation](https://nodejs.org/api/n-api.html)
- [node-addon-api C++ wrapper](https://github.com/nodejs/node-addon-api)
- [node-gyp documentation](https://github.com/nodejs/node-gyp)
- [LM Studio documentation](https://lmstudio.ai/docs)

## License

Note that LM Studio backends incorporate proprietary components. The llama.cpp library itself is under the MIT license, but the LM Studio integration layer is proprietary to Element Labs.
