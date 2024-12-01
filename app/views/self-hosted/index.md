# Self Hosted


## Table of Contents

* [Self Hosted](#self-hosted)
  * [Table of Contents](#table-of-contents)
    * [Important note](#important-note)
    * [Installation](#installation)
      * [Requirements](#requirements)
      * [Install](#install)
        * [Debug install script](#debug-install-script)
        * [Prompts](#prompts)
        * [Initial Setup (Option 1)](#initial-setup-option-1)
    * [Services](#services)
      * [Important file paths](#important-file-paths)
    * [Configuration](#configuration)
      * [Initial DNS setup](#initial-dns-setup)
    * [Onboarding](#onboarding)
    * [Testing](#testing)
      * [Creating your first alias](#creating-your-first-alias)
        * [Email server settings](#email-server-settings)
      * [Sending / Receiving your first email](#sending--receiving-your-first-email)
    * [Maintenance](#maintenance)
      * [How do I backup my data?](#how-do-i-backup-my-data)
      * [How do I renew my certificates?](#how-do-i-renew-my-certificates)
      * [How do I upgrade to the latest forward email code?](#how-do-i-upgrade-to-the-latest-forward-email-code)
      * [How do I restore from a backup?](#how-do-i-restore-from-a-backup)
    * [Troubleshooting](#troubleshooting)
      * [My docker build failed](#my-docker-build-failed)
      * [How do I know what is running?](#how-do-i-know-what-is-running)
      * [How do I know if something isn't running that should be?](#how-do-i-know-if-something-isnt-running-that-should-be)
      * [How do I find logs?](#how-do-i-find-logs)
      * [What tool(s) should I use to test email configuration best practices?](#what-tools-should-i-use-to-test-email-configuration-best-practices)
      * [What tool(s) should I use to check IP reputation?](#what-tools-should-i-use-to-check-ip-reputation)

### Important note

> This is a community-driven, self-hosted solution designed for those comfortable managing their own infrastructure. While we strive to provide comprehensive guidance and encourage community contributions, this solution is not officially supported. For a fully managed and supported experience, please explore our hosted solution at <https://forwardemail.net>.

### Installation

#### Requirements

Before running the installation script, ensure you have the following:

* **Operating System**: A Linux-based server (e.g. Ubuntu 22.04+).
* **Resources**: 4 vCPUs and 8GB RAM
* **Root Access**: Administrative privileges to execute commands.
* **Domain Name**: A custom domain ready for DNS configuration.
* **Clean IP**: Ensure your server has a clean IP address with no prior spam reputation by checking blacklists. More info [here](#what-tools-should-i-use-to-check-ip-reputation).

#### Install

Run the following command in your server to download and execute the installation script:

```sh
bash <(curl -fsSL selfhost.forwardemail.net)
```

##### Debug install script

Add DEBUG=true in front of the install script for verbose output:

```sh
DEBUG=true bash <(curl -fsSL selfhost.forwardemail.net)
```

##### Prompts

```sh
1. Initial setup
2. Setup Backups
3. Setup Auto Upgrades
4. Renew certificates
5. Restore from Backup
6. Help
7. Exit
```

* **Initial setup**: Download the latest forward email code, configure the environment, prompt for your custom domain and setup all necessary certificates, keys and secrets.
* **Setup Backup**: Will setup a cron to backup mongoDB and redis using an S3-compatible store for secure, remote storage. Separately, sqlite will be backed up on login if there are changes for secure, encrypted backups.
* **Setup Upgrade**: Setup a cron to look for nightly updates which will safely rebuild and restart infrastructure components.
* **Renew certificates**: Certbot / lets encrypt is used for SSL certificates and keys will expire every 3 months. This will renew the certificates for your domain and place them in the necessary folder for related components to consume. See [important file paths](#important-file-paths)
* **Restore from backup**: Will trigger mongodb and redis to restore from backup data.

##### Initial Setup (Option 1)

Choose option `1. Initial setup` to begin.

Once complete, you should see a success message. You can even run `docker ps` to see **the** components spun up. More information on componets below.

### Services

| Service Name | Default Port | Description                                            |
| ------------ | :----------: | ------------------------------------------------------ |
| Web          |     `443`    | Web interface for all admin interactions               |
| API          |    `4000`    | Api layer to abstract databases                        |
| Bree         |     None     | Background job and task runner                         |
| SMTP         |   `465/587`  | SMTP server for outboound email                        |
| SMTP Bree    |     None     | SMTP background job                                    |
| MX           |    `2525`    | Mail exchange for inbound email and email forwarding   |
| IMAP         |  `993/2993`  | IMAP server for inbound email and mailbox management   |
| POP3         |  `995/2995`  | POP3 server for inbound email and mailbox management   |
| SQLite       |    `3456`    | SQLite server for interactions with sqlite database(s) |
| SQLite Bree  |     None     | SQLite background job                                  |
| CalDAV       |    `5000`    | CalDAV server for calendar management                  |
| MongoDB      |    `27017`   | MongoDB database for most data management              |
| CalDAV       |    `6379`    | Redis database for caching                             |
| SQLite       |     None     | SQLite database(s) for encrypted mailboxes             |

##### Important file paths

| Component              |       Host path       | Container path               |
| ---------------------- | :-------------------: | ---------------------------- |
| MongoDB                |   `./mongo-backups`   | `/backups`                   |
| Sqlite                 |    `./sqlite-data`    | `/mnt/{SQLITE_STORAGE_PATH}` |
| Env file               |        `./.env`       | `/app/.env`                  |
| SSL certs/keys         |        `./ssl`        | `/app/ssl/`                  |
| Private key            |  `./ssl/privkey.pem`  | `/app/ssl/privkey.pem`       |
| Full chain certificate | `./ssl/fullchain.pem` | `/app/ssl/fullchain.pem`     |
| CA certificate         |    `./ssl/cert.pem`   | `/app/ssl/cert.pem`          |
| DKIM private key       |    `./ssl/dkim.key`   | `/app/ssl/dkim.key`          |

> **💡 Tip:** Save the `.env` file securely. It is critical for recovery in case of failure.

### Configuration

#### Initial DNS setup

In your DNS provider of choice, configure the appropriate DNS records. Do note anything in brackets (`<>`) is dynamic and needs to be updated with your value.

| Type  | Name          | Content                        | TTL  |
| ----- | ------------- | ------------------------------ | ---- |
| A     | <domain_name> | <ip_address>                   | auto |
| CNAME | api           | <domain_name>                  | auto |
| CNAME | caldav        | <domain_name>                  | auto |
| CNAME | fe-bounces    | <domain_name>                  | auto |
| CNAME | imap          | <domain_name>                  | auto |
| CNAME | mx            | <domain_name>                  | auto |
| CNAME | pop3          | <domain_name>                  | auto |
| CNAME | smtp          | <domain_name>                  | auto |
| MX    | <domain_name> | mx.<domain_name>               | auto |
| TXT   | <domain_name> | "v=spf1 ip4:<ip_address> -all" | auto |

### Onboarding

1. Open the Landing Page
   Navigate to https\://\<domain\_name>, replacing \<domain\_name> with the domain configured in your DNS settings. You should see the Forward Email landing page.

2. Log In and Onboard Your Domain

* Sign in with a valid email and password.
* Enter the domain name you wish to set up (this must match the DNS configuration).
* Follow the prompts to add the required **MX** and **TXT** records for verification.

3. Complete Setup

* Once verified, access the Aliases page to create your first alias.
* Optionally, configure **SMTP for outbound email** in the **Domain Settings**. This requires additional DNS records.

> **💡 Note:** No information is sent outside of your server. The self hosted option and initial account is just for the admin login and web view to manage domains, aliases and related email configurations.

### Testing

#### Creating your first alias

1. Navigate to the Aliases Page
   Open the alias management page:

```sh
https://<domain_name>/en/my-account/domains/<domain_name>/aliases
```

2. Add a New Alias

* Click **Add Alias** (top right).
* Enter the alias name and adjust email settings as needed.
* (Optional) Enable **IMAP/POP3/CalDAV** support by selecting the checkbox.
* Click **Create Alias.**

3. Set a Password

* Click **Generate Password** to create a secure password.
* This password will be required to log in to your email client.

4. Configure Your Email Client

* Use an email client like Thunderbird.
* Enter the alias name and generated password.
* Configure the **IMAP** and **SMTP** settings accordingly.

##### Email server settings

Username: `<alias name>`

| Type | Hostname           | Port | Connection Security | Authentication  |
| ---- | ------------------ | ---- | ------------------- | --------------- |
| SMTP | smtp.<domain_name> | 465  | SSL / TLS           | Normal Password |
| IMAP | imap.<domain_name> | 993  | SSL / TLS           | Normal Password |

#### Sending / Receiving your first email

Once configured, you should be able to send and receive email to your newly created and self hosted email address!

### Maintenance

#### How do I backup my data?

Follow the [install script](./Install) and choose `option 2` in the prompt.

#### How do I renew my certificates?

Follow the [install script](./Install) and choose `option 3` in the prompt.

#### How do I upgrade to the latest forward email code?

Follow the [install script](./Install) and choose `option 4` in the prompt.

#### How do I restore from a backup?

Follow the [install script](./Install) and choose `option 6` in the prompt.

### Troubleshooting

#### My docker build failed

It's possible that retrying will help in initial installation or upgrade. But, you may want to first rule out system resource constraints by checking disk availability. `docker system df` / `df -h` on linux. And rule out any firewall issues for installing dependencies from npm (`registry.npmjs.com`). If you still see issues, file a bug with log information at <https://github.com/forwardemail/forwardemail.net/issues>

#### How do I know what is running?

You can run `docker ps` to see all the running containers which is being spun up from the `docker-compose-self-hosting.yml` file. You can also run `docker ps -a` to see everything (including containers that aren't running).

#### How do I know if something isn't running that should be?

You can run `docker ps -a` to see everything (including containers that aren't running). You may see an exit log or note.

#### How do I find logs?

You can get more logs via `docker logs -f <container_name>`. If anything exited, it's likely related to the `.env` file being configured incorrectly.

Within the web UI, you can view `/admin/emails` and `/admin/logs` for outbound email logs and error logs respectively.

#### What tool(s) should I use to test email configuration best practices?

[mxtoolbox](https://mxtoolbox.com/)

[google postmaster tools](https://postmaster.google.com/)

#### What tool(s) should I use to check IP reputation?

Use your server IP address to check against the following sites if they are on a blacklist. It's, unfortunately, not uncommon for common cloud providers to have IP reputation issues do to email spam usage. If you see your IP on a blacklist, it is recommended to spin up a new server and check the new IP address.

[spamhaus](https://check.spamhaus.org/)

[spamrats](https://www.spamrats.com/)
