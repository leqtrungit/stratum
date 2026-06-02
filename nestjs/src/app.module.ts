import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { AppController } from './app.controller.js';
import { HasuraModule } from './hasura/hasura.module.js';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
    }),
    HasuraModule,
  ],
  controllers: [AppController],
})
export class AppModule {}
