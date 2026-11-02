<?php

namespace App\Console\Commands;

use Aws\Exception\AwsException;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Storage;

class StorageInit extends Command
{
    protected $signature = 'cloudpulse:storage-init';

    protected $description = 'Create the object storage bucket if it does not exist (needed for a fresh MinIO).';

    public function handle(): int
    {
        $bucket = config('filesystems.disks.s3.bucket');

        if (empty($bucket)) {
            $this->error('AWS_BUCKET is not set.');

            return self::FAILURE;
        }

        $client = Storage::disk('s3')->getClient();

        try {
            $client->headBucket(['Bucket' => $bucket]);
            $this->info("Bucket [{$bucket}] already exists.");

            return self::SUCCESS;
        } catch (AwsException $e) {
            if ($e->getStatusCode() !== 404) {
                $this->error("Cannot reach object storage: {$e->getAwsErrorCode()} {$e->getMessage()}");

                return self::FAILURE;
            }
        }

        $client->createBucket(['Bucket' => $bucket]);
        $this->info("Bucket [{$bucket}] created.");

        return self::SUCCESS;
    }
}
