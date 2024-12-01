const path = require('node:path');
const fs = require('node:fs');

const {
  S3Client,
  CreateBucketCommand,
  HeadObjectCommand
} = require('@aws-sdk/client-s3');
const { Upload } = require('@aws-sdk/lib-storage');
const Graceful = require('@ladjs/graceful');
const Redis = require('@ladjs/redis');
const hasha = require('hasha');
const ms = require('ms');
const pWaitFor = require('p-wait-for');

const sharedConfig = require('@ladjs/shared-config');
const env = require('#config/env');
const logger = require('#helpers/logger');

const breeSharedConfig = sharedConfig('BREE');
const client = new Redis(breeSharedConfig.redis, logger);

// TODO: do we want to just use process.env if we want this as a cron instead of bree job?
const S3 = new S3Client({
  region: env.AWS_REGION,
  endpoint: env.AWS_ENDPOINT_URL,
  credentials: {
    accessKeyId: env.AWS_ACCESS_KEY_ID,
    secretAccessKey: env.AWS_SECRET_ACCESS_KEY
  }
});

const graceful = new Graceful({
  redisClients: [client],
  logger
});

graceful.listen();

const tmpBackupFileName = `redis-${Date.now()}.rdb`;
const tmpBackupFile = path.join(env.REDIS_S3_BACKUPS_DIR, tmpBackupFileName);
const backupFile = path.join(env.REDIS_S3_BACKUPS_DIR, 'dump.rdb');

(async () => {
  try {
    const bgsave = await client.bgsave();
    if (bgsave !== 'Background saving started')
      throw new Error('bgsave not working');

    await pWaitFor(
      async () => {
        const infoStr = await client.info('persistence');
        const info = Object.fromEntries(
          infoStr
            .split('\r\n')
            .filter((line) => line.includes(':'))
            .map((line) => line.split(':'))
        );

        return (
          info.rdb_bgsave_in_progress === '0' &&
          info.rdb_last_bgsave_status === 'ok'
        );
      },
      { timeout: ms('1m') }
    );

    await fs.promises.copyFile(backupFile, tmpBackupFile);

    try {
      await S3.send(
        new CreateBucketCommand({
          ACL: 'private',
          Bucket: env.REDIS_S3_BACKUP_BUCKET
        })
      );
    } catch (err) {
      if (err.name !== 'BucketAlreadyOwnedByYou') throw err;
    }

    const hash = await hasha.fromFile(backupFile, { algorithm: 'sha256' });

    try {
      const obj = await S3.send(
        new HeadObjectCommand({
          Bucket: env.REDIS_S3_BACKUP_BUCKET,
          Key: tmpBackupFileName
        })
      );
      if (obj?.Metadata?.hash === hash) {
        logger.info(
          `Backup ${backupFileName} already exists with the same hash.`
        );
        return;
      }
    } catch (err) {
      if (err.name !== 'NotFound') throw err;
    }

    logger.info('Uploading backup to S3...');
    await new Upload({
      client: S3,
      params: {
        Bucket: env.REDIS_S3_BACKUP_BUCKET,
        Key: tmpBackupFileName,
        Body: fs.createReadStream(tmpBackupFile),
        Metadata: { hash }
      }
    }).done();

    logger.info(`Backup ${tmpBackupFile} uploaded successfully.`);
  } catch (err) {
    logger.error('Backup failed:', err);
  } finally {
    try {
      await fs.promises.rm(backupFile, { force: true });
    } catch (err) {
      logger.warn(`Failed to delete backup file ${tmpBackupFile}:`, err);
    }
  }

  process.exit();
})();
