const path = require('node:path');
const fs = require('node:fs');
const { exec } = require('node:child_process');
const { promisify } = require('node:util');

const {
  S3Client,
  CreateBucketCommand,
  HeadObjectCommand
} = require('@aws-sdk/client-s3');
const { Upload } = require('@aws-sdk/lib-storage');
const hasha = require('hasha');

const Graceful = require('@ladjs/graceful');
const Mongoose = require('@ladjs/mongoose');
const sharedConfig = require('@ladjs/shared-config');

const env = require('#config/env');
const logger = require('#helpers/logger');

const setupMongoose = require('#helpers/setup-mongoose');

const breeSharedConfig = sharedConfig('BREE');
const mongoose = new Mongoose({ ...breeSharedConfig.mongoose, logger });

const execAsync = promisify(exec);

const S3 = new S3Client({
  region: env.AWS_REGION,
  endpoint: env.AWS_ENDPOINT_URL,
  credentials: {
    accessKeyId: env.AWS_ACCESS_KEY_ID,
    secretAccessKey: env.AWS_SECRET_ACCESS_KEY
  }
});

const graceful = new Graceful({
  mongooses: [mongoose],
  logger
});

graceful.listen();

const backupFileName = `mongodb-backup-${Date.now()}.gz`;
const backupFile = path.join(env.MONGO_S3_BACKUPS_DIR, backupFileName);

const mongoDumpCmd = `mongodump --archive=/backups/${backupFileName} --gzip`;

(async () => {
  try {
    await setupMongoose(logger);

    logger.info('Starting MongoDB backup...');
    await execAsync(
      env.SELF_HOSTED ? `docker exec mongodb ${mongoDumpCmd}` : mongoDumpCmd
    );

    try {
      await S3.send(
        new CreateBucketCommand({
          ACL: 'private',
          Bucket: env.MONGO_S3_BACKUP_BUCKET
        })
      );
    } catch (err) {
      if (err.name !== 'BucketAlreadyOwnedByYou') throw err;
    }

    const hash = await hasha.fromFile(backupFile, { algorithm: 'sha256' });

    try {
      const obj = await S3.send(
        new HeadObjectCommand({
          Bucket: env.MONGO_S3_BACKUP_BUCKET,
          Key: backupFileName
        })
      );
      if (obj?.Metadata?.hash === hash) {
        `Backup ${backupFileName} already exists with the same hash.`;
        return;
      }
    } catch (err) {
      if (err.name !== 'NotFound') throw err;
    }

    logger.info('Uploading backup to S3...');
    const upload = new Upload({
      client: S3,
      params: {
        Bucket: env.MONGO_S3_BACKUP_BUCKET,
        Key: backupFileName,
        Body: fs.createReadStream(backupFile),
        Metadata: { hash }
      }
    });

    await upload.done();
    logger.info('Backup upload complete.');
  } catch (err) {
    logger.fatal(err);
  } finally {
    await fs.promises.rm(backupFile, { force: true });
    logger.info('Local backup file removed.');
  }

  process.exit(0);
})();
