import { UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { HasuraWebhookGuard } from './hasura-webhook.guard.js';

const makeContext = (headers: Record<string, string>) => ({
  switchToHttp: () => ({
    getRequest: () => ({ headers }),
  }),
});

describe('HasuraWebhookGuard', () => {
  let guard: HasuraWebhookGuard;
  let configService: jest.Mocked<ConfigService>;

  beforeEach(() => {
    configService = { get: jest.fn().mockReturnValue('secret-abc') } as any;
    guard = new HasuraWebhookGuard(configService);
  });

  it('allows request when secret matches', () => {
    const ctx = makeContext({ 'x-hasura-event-secret': 'secret-abc' });
    expect(guard.canActivate(ctx as any)).toBe(true);
  });

  it('rejects request with no secret header', () => {
    const ctx = makeContext({});
    expect(() => guard.canActivate(ctx as any)).toThrow(UnauthorizedException);
  });

  it('rejects request with wrong secret', () => {
    const ctx = makeContext({ 'x-hasura-event-secret': 'wrong' });
    expect(() => guard.canActivate(ctx as any)).toThrow(UnauthorizedException);
  });
});
