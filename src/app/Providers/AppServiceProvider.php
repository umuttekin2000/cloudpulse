<?php

namespace App\Providers;

use Illuminate\Cache\RateLimiting\Limit;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        //
    }

    public function boot(): void
    {

        RateLimiter::for('uploads', fn (Request $request) => Limit::perMinute(
            config('cloudpulse.uploads_per_minute'),
        )->by($request->ip()));
    }
}
