import { Test, TestingModule } from '@nestjs/testing';
import { ConfigService } from '@nestjs/config';
import { AppController } from './app.controller';

describe('AppController', () => {
  let appController: AppController;

  beforeEach(async () => {
    const app: TestingModule = await Test.createTestingModule({
      controllers: [AppController],
      providers: [
        {
          provide: ConfigService,
          useValue: { get: jest.fn().mockReturnValue('http://hasura:8080') },
        },
      ],
    }).compile();

    appController = app.get<AppController>(AppController);
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  describe('health', () => {
    it('should return ok when Hasura is healthy', async () => {
      global.fetch = jest.fn().mockResolvedValue({ ok: true }) as unknown as typeof fetch;

      const result = await appController.getHealth();
      expect(result.status).toBe('ok');
      expect(result.timestamp).toBeDefined();
      expect(result.uptime).toBeDefined();
      expect(result.dependencies.hasura.status).toBe('ok');
      expect(result.dependencies.hasura.latency_ms).toBeGreaterThanOrEqual(0);
    });

    it('should return degraded when Hasura is unreachable', async () => {
      global.fetch = jest.fn().mockRejectedValue(new Error('Connection refused')) as unknown as typeof fetch;

      const result = await appController.getHealth();
      expect(result.status).toBe('degraded');
      expect(result.dependencies.hasura.status).toBe('error');
    });

    it('should return degraded when Hasura returns non-ok status', async () => {
      global.fetch = jest.fn().mockResolvedValue({ ok: false }) as unknown as typeof fetch;

      const result = await appController.getHealth();
      expect(result.status).toBe('degraded');
      expect(result.dependencies.hasura.status).toBe('error');
    });
  });
});
