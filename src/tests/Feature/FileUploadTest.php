<?php

namespace Tests\Feature;

use App\Jobs\ProcessUploadedFile;
use App\Models\FileUpload;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Queue;
use Illuminate\Support\Facades\Storage;
use Inertia\Testing\AssertableInertia as Assert;
use Tests\TestCase;

class FileUploadTest extends TestCase
{
    use RefreshDatabase;

    public function test_dashboard_renders_with_an_empty_file_list(): void
    {
        $this->withoutVite();

        $this->get('/')
            ->assertOk()
            ->assertInertia(fn (Assert $page) => $page
                ->component('Dashboard')
                ->has('files', 0)
                ->has('app.pod'));
    }

    public function test_upload_is_stored_and_queued_for_processing(): void
    {
        Storage::fake('s3');
        Queue::fake();

        $response = $this->post('/files', [
            'file' => UploadedFile::fake()->create('report.pdf', 100, 'application/pdf'),
        ]);

        $response->assertRedirect();
        $this->assertDatabaseHas('file_uploads', [
            'original_name' => 'report.pdf',
            'status' => FileUpload::STATUS_PENDING,
        ]);
        Queue::assertPushed(ProcessUploadedFile::class);
        $this->assertCount(1, Storage::disk('s3')->allFiles('uploads'));
    }

    public function test_disallowed_file_types_are_rejected(): void
    {
        Storage::fake('s3');
        Queue::fake();

        $this->post('/files', [
            'file' => UploadedFile::fake()->create('script.exe', 10, 'application/x-msdownload'),
        ])->assertSessionHasErrors('file');

        $this->assertDatabaseCount('file_uploads', 0);
        Queue::assertNothingPushed();
    }

    public function test_job_computes_checksum_and_marks_the_file_ready(): void
    {
        Storage::fake('s3');
        Storage::disk('s3')->put('uploads/hello.txt', 'hello');

        $file = FileUpload::create([
            'original_name' => 'hello.txt',
            'disk' => 's3',
            'path' => 'uploads/hello.txt',
            'size' => 5,
        ]);

        (new ProcessUploadedFile($file->id))->handle();

        $file->refresh();
        $this->assertSame(FileUpload::STATUS_READY, $file->status);
        $this->assertSame(hash('sha256', 'hello'), $file->checksum);
    }
}
