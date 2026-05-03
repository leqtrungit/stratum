import { Module } from '@nestjs/common';
import { StorageService } from './storage.service.js';
import { StorageAction } from './storage.action.js';

@Module({
  providers: [StorageService],
  controllers: [StorageAction],
  exports: [StorageService],
})
export class StorageModule {}
