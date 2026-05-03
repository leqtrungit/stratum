import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { AppController } from './app.controller.js';
import { AppService } from './app.service.js';
import { HasuraModule } from './hasura/hasura.module.js';
// # STORAGE_START
import { StorageModule } from './storage/storage.module.js';
// # STORAGE_END

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
    }),
    HasuraModule,
    // # STORAGE_START
    StorageModule,
    // # STORAGE_END
  ],

  controllers: [AppController],
  providers: [AppService],
})
export class AppModule {}

