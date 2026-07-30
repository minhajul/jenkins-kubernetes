import { Controller, Get, Res } from '@nestjs/common';
import { Response } from 'express';
import * as client from 'prom-client';
import { AppService } from './app.service';

@Controller()
export class AppController {
  constructor(private readonly appService: AppService) {}

  @Get()
  home(): { status: string; message: string; version: string } {
    return {
      status: 'ok',
      message: 'This project is only for API usage.',
      version: '1.0.2',
    };
  }

  @Get('health')
  health(): { status: string; uptime: number } {
    return {
      status: 'ok',
      uptime: process.uptime(),
    };
  }

  @Get('metrics')
  async getMetrics(@Res() res: Response): Promise<void> {
    res.set('Content-Type', client.register.contentType);
    res.send(await client.register.metrics());
  }
}
