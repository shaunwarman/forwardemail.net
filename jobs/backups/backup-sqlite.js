const path = require('node:path');
const process = require('node:process');

const ms = require('ms');
const Piscina = require('piscina');

// eslint-disable-next-line import/no-unassigned-import
require('#config/mongoose');

const setupMongoose = require('#helpers/setup-mongoose');

const Aliases = require('#models/aliases');
const Domains = require('#models/domains');
const { encrypt } = require('#helpers/encrypt-decrypt');

const piscina = new Piscina({
  filename: path.resolve(__dirname, 'helpers', 'worker.js'),
  maxQueue: 'auto',
  idleTimeout: ms('10s'),
  maxThreads: 1
});

(async () => {
  try {
    await setupMongoose();

    if (!process.env.ALIAS_NAME)
      throw new TypeError('ALIAS_NAME process env var missing');
    if (!process.env.DOMAIN_NAME)
      throw new TypeError('DOMAIN_NAME process env var missing');
    if (!process.env.ALIAS_PASSWORD)
      throw new TypeError('ALIAS_PASSWORD process env var missing');

    const [alias, domain] = await Promise.all([
      Aliases.findOne({ name: process.env.ALIAS_NAME }),
      Domains.findOne({ name: process.env.DOMAIN_NAME })
    ]);

    if (!alias) throw new TypeError('Alias does not exist');
    if (!domain) throw new TypeError('Domain does not exist');

    const payload = {
      id: `test-${Math.random()}`,
      format: 'sqlite',
      session: {
        user: {
          username: `${alias.name}@${domain.name}`,
          password: encrypt(process.env.ALIAS_PASSWORD),
          alias_id: alias.id,
          storage_location: alias.storage_location
        }
      }
    };

    await piscina.run(payload, { name: 'backup' });

    console.log('done');
  } catch (err) {
    console.error(err);
  }

  process.exit(0);
})();
