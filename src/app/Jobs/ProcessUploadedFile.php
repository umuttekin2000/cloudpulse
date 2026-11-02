<?php

namespace App\Jobs;

use App\Models\FileUpload;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Queue\Queueable;
use Illuminate\Support\Facades\Storage;
use RuntimeException;
use Throwable;

class ProcessUploadedFile implements ShouldQueue
{
    use Queueable;

    public int $tries = 3;

    public int $backoff = 5;

    public function __construct(public readonly int $fileUploadId) {}

    public function handle(): void
    {

        $file = FileUpload::query()->useWritePdo()->find($this->fileUploadId);

        if ($file === null) {
            return;
        }

        $stream = Storage::disk($file->disk)->readStream($file->path);

        if (! is_resource($stream)) {
            throw new RuntimeException("Cannot read [{$file->path}] from disk [{$file->disk}].");
        }

        $context = hash_init('sha256');
        hash_update_stream($context, $stream);
        fclose($stream);

        $file->update([
            'checksum' => hash_final($context),
            'status' => FileUpload::STATUS_READY,
        ]);
    }

    public function failed(?Throwable $exception): void
    {
        FileUpload::query()
            ->whereKey($this->fileUploadId)
            ->update(['status' => FileUpload::STATUS_FAILED]);
    }
}
