<?php

use App\Http\Controllers\DashboardController;
use App\Http\Controllers\FileController;
use Illuminate\Support\Facades\Route;

Route::get('/', [DashboardController::class, 'index'])->name('dashboard');

Route::post('/files', [FileController::class, 'store'])
    ->middleware('throttle:uploads')
    ->name('files.store');
Route::get('/files/{file}/download', [FileController::class, 'download'])->name('files.download');
Route::delete('/files/{file}', [FileController::class, 'destroy'])->name('files.destroy');
