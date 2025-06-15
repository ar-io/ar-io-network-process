import { SESClient, SendEmailCommand } from '@aws-sdk/client-ses';

/**
 * @typedef {Object} SendEmailParams
 * @property {string | string[]} to
 * @property {string} from
 * @property {string} subject
 * @property {string} text
 * @property {string} [html]
 */

/**
 * @typedef {Object} EmailProvider
 * @property {(params: SendEmailParams) => Promise<any>} sendEmail
 */

/**
 * Email provider backed by AWS SES.
 *
 * @implements {EmailProvider}
 */
export class AWSEmailProvider {
  /**
   * @param {import('@aws-sdk/client-ses').SESClientConfig} config
   */
  constructor(config = {}) {
    this.client = new SESClient(config);
  }

  /**
   * @param {SendEmailParams} params
   */
  async sendEmail({ to, from, subject, text, html }) {
    const command = new SendEmailCommand({
      Source: from,
      Destination: { ToAddresses: Array.isArray(to) ? to : [to] },
      Message: {
        Subject: { Data: subject },
        Body: {
          Text: { Data: text },
          ...(html ? { Html: { Data: html } } : {}),
        },
      },
    });

    return this.client.send(command);
  }
}

export { AWSEmailProvider as default };
