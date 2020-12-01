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

(async () => {
  await mongoose.connect();
  // aggregate users without `alert_sent_at` or timestamp out of range
  // lookup domains collection where members has users_id
  // count domains > 20
  const usersWithManyDomains = await Domains.aggregate([
    { $match: {} },
    {
      $group: {
        _id: '$members.user',
        count: {
          $sum: 1
        }
      }
    },
    {
      $match: {
        count: {
          $gte: 20
        }
      }
    },
    {
      $unwind: '$_id'
    },
    {
      $sort: { count: -1 }
    }
  ]);

  const usersWithManyAliases = await Aliases.aggregate([
    { $match: {} },
    {
      $group: {
        _id: '$user',
        count: {
          $sum: 1
        }
      }
    },
    {
      $match: {
        count: {
          $gte: 20
        }
      }
    },
    {
      $unwind: '$_id'
    },
    { $sort: { count: -1 } }
  ]);

  // create policies of:
  // 5 aliases with 5+ recipients on each
  // 20+ aliases total
  // 20+ domains

  // TODO: format feedback
  // TODO lookup usernames?
  // email to ADMIN_EMAIL
  // setup job to run every minute
  // setup alert_sent_at and check timestamp in query
  const userDomains = await Promise.all(
    usersWithManyDomains.map((user) => Users.findById(user._id))
  );
  const userAliases = await Promise.all(
    usersWithManyAliases.map((user) => Users.findById(user._id))
  );
  const userWithDomainsEmails = userDomains.map((user, index) => {
    return { email: user.email, domains: usersWithManyDomains[index].count };
  });
  const userWithAliasesEmails = userAliases.map((user, index) => {
    return { email: user.email, domains: usersWithManyAliases[index].count };
  });

  await email({
    template: 'potential-abuse',
    message: { to },
    locals: {
      locale,
      domain: domain.toObject()
    }
  });
})();
