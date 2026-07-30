import {Controller, Get} from '@nestjs/common';
import {AppService} from './app.service';

@Controller()
export class AppController {
    constructor(private readonly appService: AppService) {
    }

    @Get()
    home(): { status: string; message: string, version: string } {
        return {
            status: 'ok',
            message: 'This project is only for API usage.',
            version: '1.0.1'
        };
    }

    @Get('health')
    health(): { status: string; uptime: number } {
        return {
            status: 'ok',
            uptime: process.uptime(),
        };
    }
}
