import { Injectable, NestMiddleware } from '@nestjs/common';
import { Request, Response, NextFunction } from 'express';
import * as client from 'prom-client';

// Collect default metrics (CPU, Memory, Event Loop, Garbage Collection)
client.collectDefaultMetrics({ prefix: 'nestjs_' });

export const httpRequestCounter = new client.Counter({
  name: 'nestjs_http_requests_total',
  help: 'Total number of HTTP requests',
  labelNames: ['method', 'route', 'status_code'],
});

export const httpRequestDuration = new client.Histogram({
  name: 'nestjs_http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5],
});

@Injectable()
export class MetricsMiddleware implements NestMiddleware {
  use(req: Request, res: Response, next: NextFunction) {
    const start = Date.now();
    res.on('finish', () => {
      const duration = (Date.now() - start) / 1000;
      const route = req.route ? req.route.path : req.path;
      const labels = {
        method: req.method,
        route: route || req.path,
        status_code: res.statusCode.toString(),
      };
      httpRequestCounter.inc(labels);
      httpRequestDuration.observe(labels, duration);
    });
    next();
  }
}
