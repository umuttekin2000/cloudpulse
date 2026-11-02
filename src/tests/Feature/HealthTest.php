<?php

namespace Tests\Feature;

use App\Services\HealthChecker;
use Mockery\MockInterface;
use Tests\TestCase;

class HealthTest extends TestCase
{
    public function test_liveness_does_not_depend_on_any_service(): void
    {
        $this->getJson('/healthz')
            ->assertOk()
            ->assertJson(['status' => 'ok']);
    }

    public function test_readiness_returns_503_when_a_dependency_is_down(): void
    {
        $this->mock(HealthChecker::class, function (MockInterface $mock) {
            $mock->shouldReceive('report')->once()->andReturn([
                'status' => 'degraded',
                'checked_at' => now()->toIso8601String(),
                'checks' => [
                    'redis' => ['status' => 'down', 'latency_ms' => null, 'error' => 'ConnectionException'],
                ],
            ]);
        });

        $this->getJson('/readyz')
            ->assertStatus(503)
            ->assertJsonPath('checks.redis.status', 'down');
    }

    public function test_readiness_returns_200_when_everything_is_up(): void
    {
        $this->mock(HealthChecker::class, function (MockInterface $mock) {
            $mock->shouldReceive('report')->once()->andReturn([
                'status' => 'ok',
                'checked_at' => now()->toIso8601String(),
                'checks' => [
                    'redis' => ['status' => 'ok', 'latency_ms' => 1.2, 'error' => null],
                ],
            ]);
        });

        $this->getJson('/readyz')->assertOk()->assertJsonPath('status', 'ok');
    }
}
