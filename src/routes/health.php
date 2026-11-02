<?php

use App\Http\Controllers\HealthController;
use Illuminate\Support\Facades\Route;

Route::get('/healthz', [HealthController::class, 'live'])->name('health.live');

Route::get('/readyz', [HealthController::class, 'ready'])->name('health.ready');

Route::get('/api/status', [HealthController::class, 'status'])->name('health.status');
