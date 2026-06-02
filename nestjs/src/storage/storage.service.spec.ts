import { ConfigService } from '@nestjs/config';
import { StorageService } from './storage.service.js';

describe('StorageService', () => {
  let service: StorageService;
  let configService: jest.Mocked<ConfigService>;

  beforeEach(() => {
    configService = {
      get: jest.fn((key: string, fallback?: string) => {
        const map: Record<string, string> = {
          S3_DEFAULT_BUCKET: 'uploads',
          S3_REGION: 'us-east-1',
          S3_ENDPOINT: 'http://localhost:9000',
          S3_ACCESS_KEY: 'access',
          S3_SECRET_KEY: 'secret',
        };
        return map[key] ?? fallback;
      }),
      getOrThrow: jest.fn((key: string) => {
        const map: Record<string, string> = {
          S3_ENDPOINT: 'http://localhost:9000',
          S3_ACCESS_KEY: 'access',
          S3_SECRET_KEY: 'secret',
        };
        if (!map[key]) throw new Error(`Missing env: ${key}`);
        return map[key];
      }),
    } as any;

    service = new StorageService(configService);
    service.onModuleInit();
  });

  describe('getPublicUrl', () => {
    it('assembles path-style URL correctly', async () => {
      const url = await service.getPublicUrl('my-file.jpg');
      expect(url).toBe('http://localhost:9000/uploads/my-file.jpg');
    });

    it('uses provided bucket over default', async () => {
      const url = await service.getPublicUrl('my-file.jpg', 'custom-bucket');
      expect(url).toBe('http://localhost:9000/custom-bucket/my-file.jpg');
    });
  });

  describe('getPresignedUploadUrl', () => {
    it('returns fileKey with timestamp-filename format', async () => {
      jest.spyOn(Date, 'now').mockReturnValue(1700000000000);

      const { fileKey } = await service.getPresignedUploadUrl({
        filename: 'photo.png',
        mimeType: 'image/png',
      });

      expect(fileKey).toBe('1700000000000-photo.png');

      jest.spyOn(Date, 'now').mockRestore();
    });
  });
});
