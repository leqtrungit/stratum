import {
  CanActivate,
  ExecutionContext,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

@Injectable()
export class HasuraWebhookGuard implements CanActivate {
  constructor(private readonly configService: ConfigService) {}

  canActivate(context: ExecutionContext): boolean {
    const request = context.switchToHttp().getRequest();
    const secret = request.headers['x-hasura-event-secret'];

    const expectedSecret = this.configService.get<string>('HASURA_EVENT_SECRET');

    if (!secret || secret !== expectedSecret) {
      throw new UnauthorizedException('Invalid Hasura event secret');
    }

    return true;
  }
}
