import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { GraphQLClient } from 'graphql-request';
// import { getSdk } from './generated/graphql.js'; // Will be available after running codegen

@Injectable()
export class HasuraService {
  private readonly logger = new Logger(HasuraService.name);
  private readonly client: GraphQLClient;
  // public readonly sdk: ReturnType<typeof getSdk>;

  constructor(private readonly configService: ConfigService) {
    const endpoint = this.configService.getOrThrow<string>('HASURA_ENDPOINT') + '/v1/graphql';
    const adminSecret = this.configService.getOrThrow<string>('HASURA_ADMIN_SECRET');

    this.client = new GraphQLClient(endpoint, {
      headers: {
        'x-hasura-admin-secret': adminSecret,
      },
    });

    // this.sdk = getSdk(this.client);
  }

  /**
   * Raw GraphQL request (for dynamic queries or before SDK is generated)
   */
  async graphql<T = any>(query: string, variables: Record<string, any> = {}): Promise<T> {
    try {
      return await this.client.request<T>(query, variables);
    } catch (error) {
      this.logger.error(`Hasura Request Failed: ${error.message}`);
      throw error;
    }
  }

  async mutate<T = any>(mutation: string, variables: Record<string, any> = {}): Promise<T> {
    return this.graphql<T>(mutation, variables);
  }

  async query<T = any>(query: string, variables: Record<string, any> = {}): Promise<T> {
    return this.graphql<T>(query, variables);
  }
}
