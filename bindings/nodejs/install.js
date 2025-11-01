#!/usr/bin/env node
/**
 * Post-install script to set up platform-specific native libraries
 * This script runs after npm install to verify bundled binaries
 */

const fs = require('fs');
const path = require('path');
const os = require('os');

function getPlatformInfo() {
  const platform = os.platform();
  const arch = os.arch();

  // Map Node.js platform to our package naming
  const platformMap = {
    'darwin': 'darwin',
    'linux': 'linux',
    'win32': 'win32'
  };

  // Map Node.js arch to our package naming
  const archMap = {
    'x64': 'x64',
    'arm64': 'arm64'
  };

  return {
    platform: platformMap[platform],
    arch: archMap[arch],
    supported: platformMap[platform] && archMap[arch]
  };
}

function main() {
  const info = getPlatformInfo();

  if (!info.supported) {
    console.warn(
      `Warning: Platform ${os.platform()}-${os.arch()} is not officially supported.\n` +
      `Pyjamaz currently supports: darwin-x64, darwin-arm64, linux-x64\n` +
      `You may need to build from source.`
    );
    return;
  }

  const platformPackage = `@pyjamaz/${info.platform}-${info.arch}`;
  const nativeDir = path.join(__dirname, 'native');

  // Check if native directory exists and contains libraries
  if (fs.existsSync(nativeDir)) {
    const files = fs.readdirSync(nativeDir);
    const hasLibrary = files.some(f =>
      f.includes('libpyjamaz') || f.includes('pyjamaz.dll')
    );

    if (hasLibrary) {
      console.log(`✓ Pyjamaz native binaries found for ${info.platform}-${info.arch}`);
      return;
    }
  }

  console.warn(
    `Warning: Native binaries not found in ${nativeDir}\n` +
    `Expected platform package: ${platformPackage}\n` +
    `This package should be installed automatically via optionalDependencies.`
  );
}

main();
