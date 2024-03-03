

## Self hosted

### Table of Contents


> Warning: Self-hosted option is for power users where the expectation of support is limited. For a managed offering, check out https://forwardemail.net.


### Setup

#### Pre-requisites

#### Installation

##### Clone the repository

Let's clone the repository, bringing in the latest source code, along with the important self hosted docker compose files and related scripts.

```sh
git clone git@github.com:forwardemail/forwardemail.net.git
```

##### Spin up the infrastructure

Use docker-compose to spin up our environment. We'll talk more below on the configuration options and the high level architecture of each component being used.

```sh
docker-compose -f docker-compose-self-hosted.yml up -d
```

#### Configuration


### Architecture

#### High level

#### Components


### Usage

#### Setting up a domain

#### Setting up email

##### Inbound (IMAP)

##### Outbound (SMTP)

##### Receiving an email

##### Sending an email


### Hosting

#### Deploying to X

#### Deploying to Y




#### TODO
- Why is bree exiting? Memory / CPU limits
- Can we remove or limit bree for things specific to self hosted?
  - Look at every job to see if it should stay or go (be wrapped in if self_hosted=true variable)
- Remove billing and background jobs to look for payment
- end to end setup
- customize configuration or add tool where needed
- Document how each component works and fits together
- Cache build steps (checksum based)
- fix local development
- dnsmasq for local hostname configuration and testing
  - is there a UI for configuration domain names locally? And updating records?
- redo the sqlite image
- How to maintain self hosted setup (how to update, maintain data, backups, recovery, etc)
- Fix has_smtp checks
- development mode will only send preview emails, we need to get production env to work
- redis-cli KEYS "auth_limit*" | xargs redis-cli DEL
  - because imap died with wildduck SNI issue and then login fails


### Inspiration
https://supabase.com/docs/guides/self-hosting
https://github.com/supabase/supabase/blob/master/docker/docker-compose.yml
https://docs.plane.so/self-hosting/docker-compose
https://blog.stackblitz.com/posts/stackblitz-self-hosted/




Here's a checklist in a concise format to help alleviate common issues when self-hosting email:

IP Reputation:
- [ ] Regularly check the reputation of your server's IP address using reputable IP blacklist monitoring services.
- [ ] Ensure that your server's IP address has not been previously associated with spam or abusive behavior.

Authentication and Encryption:
- [ ] Configure SPF, DKIM, and DMARC records correctly for your domain to authenticate your emails.
- [ ] Implement TLS encryption for email transmission to protect the privacy and integrity of your messages.

SPF/DKIM/DMARC Setup:
- [ ] Create and maintain accurate SPF records to specify which servers are allowed to send emails on behalf of your domain.
- [ ] Set up DKIM signing to add cryptographic signatures to your outgoing emails, proving their authenticity.
- [ ] Implement DMARC policies to specify how recipient email servers should handle emails that fail SPF and/or DKIM authentication.

Reverse DNS (rDNS):
- [ ] Ensure that your mail server's IP address has a valid reverse DNS (rDNS) entry that resolves to a hostname matching your domain.
- [ ] Contact your Internet Service Provider (ISP) or hosting provider to set up or correct the rDNS entry if necessary.

Content and Formatting:
- [ ] Craft clear, concise, and relevant email content with a focus on providing value to recipients.
- [ ] Avoid using spam-triggering language, deceptive subject lines, excessive use of images, and misleading formatting.
- [ ] Comply with HTML and MIME standards to ensure that your emails are properly formatted and rendered across different email clients.

Volume and Frequency:
- [ ] Monitor and manage your email sending volume and frequency to avoid triggering spam filters.
- [ ] Gradually ramp up your email sending volume to establish a positive sending reputation gradually.

Monitoring and Feedback Loops:
- [ ] Set up email monitoring tools and feedback loops to track email delivery metrics, bounce rates, and spam complaint rates.
- [ ] Actively monitor email deliverability performance and promptly address any issues or anomalies detected.

IP Address Reputation Services:
- [ ] Subscribe to reputable IP reputation services or use reputation monitoring tools to monitor the reputation of your server's IP address.
- [ ] Take corrective actions, such as requesting delisting from blacklists, if your server's IP address is listed.