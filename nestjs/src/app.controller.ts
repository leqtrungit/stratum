import { Controller, Get } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

@Controller()
export class AppController {
  constructor(private readonly configService: ConfigService) {}

  @Get('health')
  async getHealth() {
    const hasuraEndpoint = this.configService.get<string>('HASURA_ENDPOINT', 'http://hasura:8080');
    const hasura = await this.checkDependency(`${hasuraEndpoint}/healthz`);

    return {
      status: hasura.status === 'ok' ? 'ok' : 'degraded',
      timestamp: new Date().toISOString(),
      uptime: process.uptime(),
      dependencies: { hasura },
    };
  }

  private async checkDependency(url: string): Promise<{ status: 'ok' | 'error'; latency_ms: number }> {
    const start = Date.now();
    try {
      const res = await fetch(url, { signal: AbortSignal.timeout(3000) });
      return { status: res.ok ? 'ok' : 'error', latency_ms: Date.now() - start };
    } catch {
      return { status: 'error', latency_ms: Date.now() - start };
    }
  }
}
