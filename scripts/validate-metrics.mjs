// Validate metrics.json against contracts/metrics.schema.json — locks the
// client<->pipeline contract. Uses ajv (already pulled in via the workflow's npm deps).
import Ajv from 'ajv/dist/2020.js';
import addFormats from 'ajv-formats';
import { readFile } from 'node:fs/promises';

const schema = JSON.parse(await readFile('contracts/metrics.schema.json', 'utf8'));
const data = JSON.parse(await readFile(process.argv[2] || 'metrics.json', 'utf8'));

const ajv = new Ajv({ allErrors: true, strict: false });
addFormats(ajv);
const validate = ajv.compile(schema);
const ok = validate(data);
if (!ok) {
  console.error('validate: FAIL');
  for (const e of validate.errors) console.error(`  ${e.instancePath || '/'} ${e.message}`);
  process.exit(1);
}
console.log('validate: metrics.json conforms to schema');
