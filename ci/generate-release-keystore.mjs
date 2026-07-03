/**
 * Gera ci/unitecfv-release.p12 (PKCS12) com credenciais fixas.
 * Rode uma vez: node ci/generate-release-keystore.mjs
 */
import forge from 'node-forge';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const out = path.join(__dirname, 'unitecfv-release.p12');
const password = 'unitecfv2026';
const alias = 'unitecfv';

const keys = forge.pki.rsa.generateKeyPair(2048);
const cert = forge.pki.createCertificate();
cert.publicKey = keys.publicKey;
cert.serialNumber = '01';
cert.validity.notBefore = new Date();
cert.validity.notAfter = new Date();
cert.validity.notAfter.setFullYear(cert.validity.notBefore.getFullYear() + 25);
const attrs = [
  { name: 'commonName', value: 'Unitec Forca de Vendas' },
  { name: 'organizationalUnitName', value: 'Mobile' },
  { name: 'organizationName', value: 'Unitec' },
  { name: 'countryName', value: 'BR' },
];
cert.setSubject(attrs);
cert.setIssuer(attrs);
cert.sign(keys.privateKey, forge.md.sha256.create());

const p12Asn1 = forge.pkcs12.toPkcs12Asn1(
  keys.privateKey,
  [cert],
  password,
  { generateLocalKeyId: true, friendlyName: alias },
);
const p12Der = forge.asn1.toDer(p12Asn1).getBytes();
fs.writeFileSync(out, Buffer.from(p12Der, 'binary'));
console.log(`Keystore gerada: ${out}`);
console.log(`Alias: ${alias}`);
console.log(`Senha (store/key): ${password}`);
