<?php

namespace App\Services;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Redis;
use Illuminate\Support\Facades\Storage;
use Throwable;

class HealthChecker
{
    /**
     * 
     *
     * @return array{status: string, checked_at: string, checks: array<string, array{status: string, latency_ms: float|null, error: string|null}>}
     */
    public function report(): array
    {
        $checks = [
            'mysql_primary' => $this->measure(fn () => DB::connection()->getPdo()->query('SELECT 1')),
            'mysql_replica' => $this->measure(fn () => DB::connection()->getReadPdo()->query('SELECT 1')),
            'redis' => $this->measure(fn () => Redis::connection()->ping()),
            's3' => $this->measure(fn () => Storage::disk('s3')->getClient()->headBucket([
                'Bucket' => config('filesystems.disks.s3.bucket'),
            ])),
        ];

        $healthy = collect($checks)->every(fn (array $check) => $check['status'] === 'ok');

        return [
            'status' => $healthy ? 'ok' : 'degraded',
            'checked_at' => now()->toIso8601String(),
            'checks' => $checks,
        ];
    }

    /**
     * @return array{status: string, latency_ms: float|null, error: string|null}
     */
    private function measure(callable $probe): array
    {
        $start = hrtime(true);

        try {
            $probe();

            return [
                'status' => 'ok',
                'latency_ms' => round((hrtime(true) - $start) / 1_000_000, 1),
                'error' => null,
            ];
        } catch (Throwable $e) {
            
            Log::warning('Health check failed', [
                'exception' => $e::class,
                'message' => $e->getMessage(),
            ]);

            return [
                'status' => 'down',
                'latency_ms' => null,
                'error' => class_basename($e),
            ];
        }
    }
}
