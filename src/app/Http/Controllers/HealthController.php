<?php

namespace App\Http\Controllers;

use App\Services\HealthChecker;
use Illuminate\Http\JsonResponse;

class HealthController extends Controller
{
    public function __construct(private readonly HealthChecker $health) {}

    public function live(): JsonResponse
    {
        return response()->json(['status' => 'ok']);
    }

    public function ready(): JsonResponse
    {
        $report = $this->health->report();

        return response()->json($report, $report['status'] === 'ok' ? 200 : 503);
    }

    public function status(): JsonResponse
    {
        return response()->json($this->health->report() + [
            'app' => [
                'version' => config('cloudpulse.version'),
                'pod' => gethostname(),
            ],
        ]);
    }
}
