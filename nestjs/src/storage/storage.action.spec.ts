import { BadRequestException } from '@nestjs/common';
import { StorageAction } from './storage.action.js';
import { StorageService } from './storage.service.js';
import { HasuraService } from '../hasura/hasura.service.js';

describe('StorageAction', () => {
  let action: StorageAction;
  let storageService: jest.Mocked<StorageService>;
  let hasuraService: jest.Mocked<HasuraService>;

  beforeEach(() => {
    storageService = {
      getPublicUrl: jest.fn().mockResolvedValue('http://s3/bucket/key'),
      getPresignedUploadUrl: jest.fn().mockResolvedValue({ uploadUrl: 'http://presigned', fileKey: 'key' }),
      deleteFile: jest.fn().mockResolvedValue(undefined),
    } as any;

    hasuraService = {
      mutate: jest.fn().mockResolvedValue({
        insert_files_one: { id: 'uuid-1', url: 'http://s3/f', size: 100, mime_type: 'image/png', created_at: '2024-01-01' },
      }),
      query: jest.fn(),
    } as any;

    action = new StorageAction(storageService, hasuraService);
  });

  describe('confirmUpload', () => {
    it('throws BadRequestException when userId missing', async () => {
      await expect(
        action.confirmUpload({
          input: { fileKey: 'key', size: 100, mimeType: 'image/png' },
          session_variables: {},
        }),
      ).rejects.toThrow(BadRequestException);
    });

    it('calls storageService and hasura when userId present', async () => {
      const result = await action.confirmUpload({
        input: { fileKey: 'key', size: 100, mimeType: 'image/png' },
        session_variables: { 'x-hasura-user-id': 'user-1' },
      });

      expect(storageService.getPublicUrl).toHaveBeenCalledWith('key');
      expect(hasuraService.mutate).toHaveBeenCalled();
      expect(result.id).toBe('uuid-1');
    });
  });

  describe('deleteFile', () => {
    it('throws BadRequestException when file not found', async () => {
      hasuraService.query.mockResolvedValue({ files_by_pk: null });

      await expect(
        action.deleteFile({
          input: { fileId: 'missing-id' },
          session_variables: { 'x-hasura-user-id': 'user-1' },
        }),
      ).rejects.toThrow(BadRequestException);
    });

    it('throws BadRequestException when user is not the owner', async () => {
      hasuraService.query.mockResolvedValue({
        files_by_pk: { key: 'k', bucket: 'b', created_by: 'other-user' },
      });

      await expect(
        action.deleteFile({
          input: { fileId: 'file-1' },
          session_variables: { 'x-hasura-user-id': 'user-1' },
        }),
      ).rejects.toThrow(BadRequestException);
    });

    it('deletes from S3 and soft-deletes in DB when owner requests', async () => {
      hasuraService.query.mockResolvedValue({
        files_by_pk: { key: 'k', bucket: 'b', created_by: 'user-1' },
      });
      hasuraService.mutate.mockResolvedValue({ update_files_by_pk: { id: 'file-1' } });

      const result = await action.deleteFile({
        input: { fileId: 'file-1' },
        session_variables: { 'x-hasura-user-id': 'user-1' },
      });

      expect(storageService.deleteFile).toHaveBeenCalledWith('k', 'b');
      expect(hasuraService.mutate).toHaveBeenCalled();
      expect(result).toEqual({ success: true });
    });
  });
});
