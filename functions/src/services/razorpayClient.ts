import * as crypto from 'crypto';

export interface RazorpayOrderResult {
  id: string;
  amount: number; // in paise
  currency: string;
  receipt: string;
  status: string;
}

export interface RazorpayRefundResult {
  id: string;
  paymentId: string;
  amount: number;
  status: string;
}

export class RazorpayClient {
  private keyId: string;
  private keySecret: string;
  private webhookSecret: string;

  constructor(options?: {
    keyId?: string;
    keySecret?: string;
    webhookSecret?: string;
  }) {
    this.keyId =
      options?.keyId ||
      process.env.RAZORPAY_KEY_ID ||
      'rzp_test_TCXezMGngEewk7';
    this.keySecret =
      options?.keySecret ||
      process.env.RAZORPAY_KEY_SECRET ||
      'qM8be9p0FHYNMQ0F3dDUcl35';
    this.webhookSecret =
      options?.webhookSecret ||
      process.env.RAZORPAY_WEBHOOK_SECRET ||
      'test_webhook_secret_key_12345';
  }

  public getKeyId(): string {
    return this.keyId;
  }

  public getKeySecret(): string {
    return this.keySecret;
  }

  public getWebhookSecret(): string {
    return this.webhookSecret;
  }

  private getAuthHeader(): string {
    const creds = `${this.keyId}:${this.keySecret}`;
    return `Basic ${Buffer.from(creds).toString('base64')}`;
  }

  /**
   * Creates an order with Razorpay REST API
   */
  public async createOrder(params: {
    amountPaise: number;
    receipt: string;
  }): Promise<RazorpayOrderResult> {
    const { amountPaise, receipt } = params;

    // Check if running in a mock unit-test environment without network
    if (process.env.MOCK_RAZORPAY === 'true') {
      return {
        id: `order_mock_${Date.now()}_${Math.floor(Math.random() * 1000)}`,
        amount: amountPaise,
        currency: 'INR',
        receipt,
        status: 'created',
      };
    }

    const response = await fetch('https://api.razorpay.com/v1/orders', {
      method: 'POST',
      headers: {
        Authorization: this.getAuthHeader(),
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        amount: amountPaise,
        currency: 'INR',
        receipt,
      }),
    });

    if (!response.ok) {
      const errText = await response.text();
      throw new Error(`Razorpay Order creation failed (${response.status}): ${errText}`);
    }

    const data = (await response.json()) as any;
    return {
      id: data.id,
      amount: data.amount,
      currency: data.currency,
      receipt: data.receipt,
      status: data.status,
    };
  }

  /**
   * Verifies the checkout HMAC-SHA256 payment signature with constant-time equality
   */
  public verifyPaymentSignature(params: {
    orderId: string;
    paymentId: string;
    signature: string;
  }): boolean {
    const { orderId, paymentId, signature } = params;
    if (!orderId || !paymentId || !signature) return false;

    try {
      const payload = `${orderId}|${paymentId}`;
      const expectedSignature = crypto
        .createHmac('sha256', this.keySecret)
        .update(payload)
        .digest('hex');

      if (expectedSignature.length !== signature.length) return false;

      return crypto.timingSafeEqual(
        Buffer.from(expectedSignature, 'hex'),
        Buffer.from(signature, 'hex')
      );
    } catch {
      return false;
    }
  }

  /**
   * Verifies a Razorpay Webhook signature (X-Razorpay-Signature header) with constant-time equality
   */
  public verifyWebhookSignature(params: {
    rawBody: string | Buffer;
    signature: string;
    customSecret?: string;
  }): boolean {
    const { rawBody, signature, customSecret } = params;
    const secret = customSecret || this.webhookSecret;
    if (!rawBody || !signature || !secret) return false;

    try {
      const expectedSignature = crypto
        .createHmac('sha256', secret)
        .update(rawBody)
        .digest('hex');

      if (expectedSignature.length !== signature.length) return false;

      return crypto.timingSafeEqual(
        Buffer.from(expectedSignature, 'hex'),
        Buffer.from(signature, 'hex')
      );
    } catch {
      return false;
    }
  }

  /**
   * Issues a refund for a payment via Razorpay REST API
   */
  public async refundPayment(params: {
    paymentId: string;
    amountPaise?: number;
    reason?: string;
  }): Promise<RazorpayRefundResult> {
    const { paymentId, amountPaise, reason } = params;

    if (process.env.MOCK_RAZORPAY === 'true') {
      return {
        id: `rfnd_mock_${Date.now()}`,
        paymentId,
        amount: amountPaise || 0,
        status: 'processed',
      };
    }

    const body: Record<string, any> = {};
    if (amountPaise) body.amount = amountPaise;
    if (reason) body.notes = { reason };

    const response = await fetch(`https://api.razorpay.com/v1/payments/${paymentId}/refund`, {
      method: 'POST',
      headers: {
        Authorization: this.getAuthHeader(),
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
    });

    if (!response.ok) {
      const errText = await response.text();
      throw new Error(`Razorpay Refund failed (${response.status}): ${errText}`);
    }

    const data = (await response.json()) as any;
    return {
      id: data.id,
      paymentId: data.payment_id || paymentId,
      amount: data.amount,
      status: data.status,
    };
  }
}

// Singleton provider
let defaultClient: RazorpayClient | null = null;

export function getRazorpayClient(): RazorpayClient {
  if (!defaultClient) {
    defaultClient = new RazorpayClient();
  }
  return defaultClient;
}

export function setRazorpayClient(client: RazorpayClient | null): void {
  defaultClient = client;
}
