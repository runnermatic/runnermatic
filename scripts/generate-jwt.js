#!/usr/bin/env node
'use strict';

const crypto = require('crypto');
const fs = require('fs');

const appId = process.env.GITHUB_APP_ID;
const keyPath = process.env.GITHUB_APP_PRIVATE_KEY_PATH;

if (!appId || !keyPath) {
  console.error('ERROR: GITHUB_APP_ID and GITHUB_APP_PRIVATE_KEY_PATH must be set');
  process.exit(1);
}

const privateKey = fs.readFileSync(keyPath, 'utf8');

const now = Math.floor(Date.now() / 1000);
const header = { alg: 'RS256', typ: 'JWT' };
const payload = {
  iss: appId,
  iat: now - 60,
  exp: now + (10 * 60)
};

function base64url(obj) {
  return Buffer.from(JSON.stringify(obj))
    .toString('base64')
    .replace(/=/g, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');
}

const headerB64 = base64url(header);
const payloadB64 = base64url(payload);
const signingInput = `${headerB64}.${payloadB64}`;

const sign = crypto.createSign('RSA-SHA256');
sign.update(signingInput);
const signature = sign.sign(privateKey, 'base64')
  .replace(/=/g, '')
  .replace(/\+/g, '-')
  .replace(/\//g, '_');

console.log(`${signingInput}.${signature}`);
