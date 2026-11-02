<?php

namespace App\Http\Controllers;

use App\Http\Requests\StoreFileRequest;
use App\Jobs\ProcessUploadedFile;
use App\Models\FileUpload;
use Illuminate\Http\RedirectResponse;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Symfony\Component\HttpFoundation\StreamedResponse;

class FileController extends Controller
{
    public function store(StoreFileRequest $request): RedirectResponse
    {
        $disk = config('cloudpulse.disk');
        $upload = $request->file('file');
        $size = $upload->getSize();

        $path = $upload->store('uploads/'.now()->format('Y/m'), $disk);

        if ($path === false) {
            return back()->withErrors([
                'file' => 'The file could not be written to object storage. Check the storage service status above and try again.',
            ]);
        }

        $file = FileUpload::create([
            'original_name' => Str::limit($upload->getClientOriginalName(), 255, ''),
            'disk' => $disk,
            'path' => $path,
            'mime_type' => $upload->getMimeType(),
            'size' => $size,
            'status' => FileUpload::STATUS_PENDING,
        ]);

        ProcessUploadedFile::dispatch($file->id);

        return back()->with('success', "{$file->original_name} was uploaded and is being processed.");
    }

    public function download(FileUpload $file): StreamedResponse
    {
        $storage = Storage::disk($file->disk);

        abort_unless($storage->exists($file->path), 404);

        return $storage->download($file->path, $file->original_name);
    }

    public function destroy(FileUpload $file): RedirectResponse
    {
        Storage::disk($file->disk)->delete($file->path);
        $file->delete();

        return back()->with('success', "{$file->original_name} was deleted.");
    }
}
