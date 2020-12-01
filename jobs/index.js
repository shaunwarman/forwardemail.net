const { boolean } = require('boolean');

// const config = require('../config');

const jobs = [
  'migration',
  'vanity-domains',
  { name: 'billing', interval: 'at 7:40 pm' },
  {
    name: 'check-domains',
    timeout: '1m', // give migration script time to run
    interval: '1m'
  },
  {
    name: 'welcome-email',
    interval: '1m',
    timeout: 0
  },
  // {
  //   name: 'launch-email',
  //   date: config.launchDate
  // },
  {
    name: 'account-updates',
    interval: '1m',
    timeout: 0
  },
  {
    name: 'remove-unverified-users',
    interval: '1h',
    timeout: 0
  },
  {
    name: 'check-unknown-payment-methods',
    interval: '1h',
    timeout: 0
  },
  {
    name: 'potential-abuse',
    interval: '15m'
  }
];

if (process.env.NODE_ENV === 'production') {
  jobs.push({
    name: 'translate-phrases',
    interval: '1h',
    timeout: 0
  });
  jobs.push({
    name: 'translate-markdown',
    interval: '30m',
    timeout: 0
  });
}

if (boolean(process.env.AUTH_OTP_ENABLED))
  jobs.push({
    name: 'two-factor-reminder',
    interval: '3h',
    timeout: 0
  });

module.exports = jobs;
