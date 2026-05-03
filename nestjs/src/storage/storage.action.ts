import { Controller, Post, Body, UseGuards, BadRequestException } from '@nestjs/common';
import { StorageService } from './storage.service.js';
import { HasuraService } from '../hasura/hasura.service.js';
import { HasuraWebhookGuard } from '../common/guards/hasura-webhook.guard.js';

@Controller('actions')
@UseGuards(HasuraWebhookGuard)
export class StorageAction {
  constructor(
    private readonly storageService: StorageService,
    private readonly hasura: HasuraService,
  ) {}

  @Post('request-upload-url')
  async requestUploadUrl(@Body() body: any) {
    const { input } = body;
    return this.storageService.getPresignedUploadUrl({
      filename: input.filename,
      mimeType: input.mimeType,
      bucket: input.bucket,
    });
  }

  @Post('confirm-upload')
  async confirmUpload(@Body() body: any) {
    const { input, session_variables } = body;
    const userId = session_variables['x-hasura-user-id'];

    if (!userId) {
      throw new BadRequestException('User ID missing from session variables');
    }

    const url = await this.storageService.getPublicUrl(input.fileKey);

    const mutation = `
      mutation ConfirmUpload($obj: files_insert_input!) {
        insert_files_one(object: $obj) {
          id
          url
          size
          mime_type
          created_at
        }
      }
    `;

    const result = await this.hasura.mutate(mutation, {
      obj: {
        key: input.fileKey,
        url,
        size: input.size,
        mime_type: input.mimeType,
        bucket: process.env.S3_DEFAULT_BUCKET,
        created_by: userId,
        updated_by: userId,
      },
    });

    const file = result.insert_files_one;

    return {
      id: file.id,
      url: file.url,
      size: file.size,
      mimeType: file.mime_type,
      createdAt: file.created_at,
    };
  }

  @Post('delete-file')
  async deleteFile(@Body() body: any) {
    const { input, session_variables } = body;
    const userId = session_variables['x-hasura-user-id'];

    const query = `
      query GetFile($id: uuid!) {
        files_by_pk(id: $id) {
          key
          bucket
          created_by
        }
      }
    `;

    const result = await this.hasura.query(query, { id: input.fileId });
    const file = result.files_by_pk;

    if (!file) {
      throw new BadRequestException('File not found');
    }

    // Security check: only creator can delete
    if (file.created_by !== userId) {
      throw new BadRequestException('Unauthorized to delete this file');
    }

    // 1. Delete from S3
    await this.storageService.deleteFile(file.key, file.bucket);

    // 2. Soft delete in DB
    const softDeleteMutation = `
      mutation SoftDeleteFile($id: uuid!, $now: timestamptz!, $userId: uuid!) {
        update_files_by_pk(
          pk_columns: { id: $id },
          _set: { deleted_at: $now, deleted_by: $userId, updated_by: $userId }
        ) {
          id
        }
      }
    `;

    await this.hasura.mutate(softDeleteMutation, {
      id: input.fileId,
      now: new Date().toISOString(),
      userId,
    });

    return { success: true };
  }
}
