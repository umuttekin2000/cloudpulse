<?php

namespace App\Http\Controllers;

use App\Models\FileUpload;
use Inertia\Inertia;
use Inertia\Response;

class DashboardController extends Controller
{
    public function index(): Response
    {
        return Inertia::render('Dashboard', [
            'app' => [
                'name' => config('app.name'),
                'env' => config('app.env'),
                'version' => config('cloudpulse.version'),
                'commit' => config('cloudpulse.commit'),
                
                'pod' => gethostname(),
            ],
            'limits' => [
                'max_upload_kb' => config('cloudpulse.max_upload_kb'),
                'extensions' => config('cloudpulse.allowed_extensions'),
            ],
            'pollSeconds' => config('cloudpulse.status_poll_seconds'),

            
            'files' => fn () => FileUpload::query()
                ->latest()
                ->limit(50)
                ->get()
                ->map(fn (FileUpload $file) => [
                    'id' => $file->id,
                    'name' => $file->original_name,
                    'size' => $file->size,
                    'status' => $file->status,
                    'checksum' => $file->checksum,
                    'created_at' => $file->created_at?->toIso8601String(),
                ]),
        ]);
    }
}
