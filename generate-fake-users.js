const Frisbee = require('frisbee');
const Mongoose = require('@ladjs/mongoose');
const _ = require('lodash');

const Users = require('./app/models/user');
const Domains = require('./app/models/domain');
const Aliases = require('./app/models/alias');

const faker = require('faker');

const api = require('./api');
const web = require('./web');
const config = require('./config');
const logger = require('./helpers/logger');

const mongoUri = 'mongodb://localhost:27017/forwardemail_test';
const mongoose = new Mongoose(
  _.merge(
    {
      logger
    },
    api.config.mongoose,
    config.mongoose,
    {
      mongo: {
        uri: mongoUri
      }
    }
  )
);

// 5 aliases with 5+ recipients on each
// 20+ aliases total
// 20+ domains
async function generateRandomUsers(count) {
  for (let num = 0; num < count; num++) {
    let aliases = 1;
    const email = faker.internet.email();
    let domains = [faker.internet.domainName()];
    let recipients = [faker.internet.email()];

    if (num % 10 === 0) {
      aliases = 5;
      recipients = new Array(10)
        .fill()
        .map((recipient) => faker.internet.email());
    }

    if (num % 21 === 0) aliases = 20;
    if (num % 32 === 0)
      domains = new Array(20)
        .fill()
        .map((domain) => faker.internet.domainName());

    // generate user
    const userQuery = {
      email,
      group: 'admin'
    };
    userQuery[config.userFields.hasVerifiedEmail] = true;
    userQuery[config.userFields.hasSetPassword] = true;
    const user = await Users.register(userQuery, 'test123');

    // generate domain(s)
    let domainName = null;
    for (domainName of domains) {
      const domain = await Domains.create({
        is_api: false,
        members: [{ user: user._id, group: 'admin' }],
        name: domainName,
        is_global: false,
        locale: 'en',
        plan: 'free'
      });

      // generate alias(es)
      const alias = null;
      for (let numAliases = 0; numAliases <= aliases; numAliases++) {
        const email = faker.internet.userName();
        await Aliases.create({
          is_api: false,
          user: user._id,
          domain: domain._id,
          name: email,
          recipients,
          locale: 'en'
        });
      }
    }
  }
}

(async () => {
  await mongoose.connect(mongoUri);
  await generateRandomUsers(100);
})();
