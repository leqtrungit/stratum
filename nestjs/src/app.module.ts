import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { AppController } from './app.controller.js';
import { AppService } from './app.service.js';
import { HasuraModule } from './hasura/hasura.module.js';
import { StorageModule } from './storage/storage.module.js';

const storageEnabled = process.env.STORAGE_ENABLED === 'true';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
    }),
    HasuraModule,
    ...(storageEnabled ? [StorageModule] : []),
  ],
  controllers: [AppController],
  providers: [AppService],
})
export class AppModule {}
