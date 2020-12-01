// eslint-disable-next-line import/no-unassigned-import
require('../config/env');

const { parentPort } = require('worker_threads');

const Graceful = require('@ladjs/graceful');
const Mongoose = require('@ladjs/mongoose');
const _ = require('lodash');
const sharedConfig = require('@ladjs/shared-config');
const humanize = require('humanize-string');
const titleize = require('titleize');

const config = require('../config');
const logger = require('../helpers/logger');
const email = require('../helpers/email');

const bree = require('../bree');

const Users = require('../app/models/user');

const breeSharedConfig = sharedConfig('BREE');

const mongoose = new Mongoose({ ...breeSharedConfig.mongoose, logger });

const graceful = new Graceful({
  mongooses: [mongoose],
  brees: [bree],
  logger
});

graceful.listen();

(async () => {
  await mongoose.connect();

  // TODO: set `alert_sent_at` and check timestamp
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

  let aliasAbuseList = [];
  if (!_.isEmpty(usersWithManyAliases)) {
    const userAliases = await Promise.all(
      usersWithManyAliases.map((user) => Users.findById(user._id))
    );
    aliasAbuseList = userAliases.map((user, index) => {
      return { email: user.email, domains: usersWithManyAliases[index].count };
    });
  }

  let domainAbuseList = [];
  if (!_.isEmpty(usersWithManyDomains)) {
    const userDomains = await Promise.all(
      usersWithManyDomains.map((user) => Users.findById(user._id))
    );
    domainAbuseList = userDomains.map((user, index) => {
      return { email: user.email, domains: usersWithManyDomains[index].count };
    });
  }

  if (_.isEmpty(aliasAbuseList) && _.isEmpty(domainAbuseList)) return;

  // send potential account abuse email
  try {
    await email({
      template: 'potential-abuse',
      message: { to: config.email.message.from },
      locals: {
        locale,
        domainAbuseList,
        aliasAbuseList
      }
    });
  } catch (err) {
    logger.error(err);
  }

  if (parentPort) parentPort.postMessage('done');
  else process.exit(0);
})();
