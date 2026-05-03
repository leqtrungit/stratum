import { Module, Global } from '@nestjs/common';
import { HasuraService } from './hasura.service.js';

@Global()
@Module({
  providers: [HasuraService],
  exports: [HasuraService],
})
export class HasuraModule {}
