<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class FileUpload extends Model
{
    public const STATUS_PENDING = 'pending';

    public const STATUS_READY = 'ready';

    public const STATUS_FAILED = 'failed';

    protected $fillable = [
        'original_name',
        'disk',
        'path',
        'mime_type',
        'size',
        'checksum',
        'status',
    ];

    protected function casts(): array
    {
        return [
            'size' => 'integer',
        ];
    }
}
