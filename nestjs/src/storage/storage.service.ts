import { Injectable, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import {
  S3Client,
  PutObjectCommand,
  DeleteObjectCommand,
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';

@Injectable()
export class StorageService implements OnModuleInit {
  private s3Client: S3Client;
  private readonly defaultBucket: string;

  constructor(private readonly configService: ConfigService) {
    this.defaultBucket = this.configService.get<string>('GARAGE_DEFAULT_BUCKET', 'uploads');
  }

  onModuleInit() {
    this.s3Client = new S3Client({
      region: this.configService.get<string>('GARAGE_REGION', 'garage'),
      endpoint: this.configService.getOrThrow<string>('GARAGE_ENDPOINT'),
      credentials: {
        accessKeyId: this.configService.getOrThrow<string>('GARAGE_ACCESS_KEY'),
        secretAccessKey: this.configService.getOrThrow<string>('GARAGE_SECRET_KEY'),
      },
      forcePathStyle: true, // Required for Garage/Minio
    });
  }

  async getPresignedUploadUrl(options: {
    bucket?: string;
    filename: string;
    mimeType: string;
    expiresIn?: number;
  }) {
    const bucket = options.bucket || this.defaultBucket;
    const fileKey = `${Date.now()}-${options.filename}`;

    const command = new PutObjectCommand({
      Bucket: bucket,
      Key: fileKey,
      ContentType: options.mimeType,
    });

    const uploadUrl = await getSignedUrl(this.s3Client, command, {
      expiresIn: options.expiresIn || 300,
    });

    return { uploadUrl, fileKey };
  }

  async getPublicUrl(key: string, bucket?: string) {
    const b = bucket || this.defaultBucket;
    const endpoint = this.configService.getOrThrow<string>('GARAGE_ENDPOINT');
    // Basic URL construction for Garage path-style access
    return `${endpoint}/${b}/${key}`;
  }

  async deleteFile(key: string, bucket?: string) {
    const b = bucket || this.defaultBucket;
    const command = new DeleteObjectCommand({
      Bucket: b,
      Key: key,
    });
    await this.s3Client.send(command);
  }
}
