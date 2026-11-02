import { useRef } from 'react';
import { useForm } from '@inertiajs/react';

export default function UploadPanel({ limits }) {
    const input = useRef(null);
    const { data, setData, post, processing, progress, errors, reset } = useForm({
        file: null,
    });

    const maxMb = Math.round(limits.max_upload_kb / 1024);

    function submit(event) {
        event.preventDefault();
        post('/files', {
            forceFormData: true,
            preserveScroll: true,
            onSuccess: () => {
                reset();
                if (input.current) {
                    input.current.value = '';
                }
            },
        });
    }

    return (
        <section className="panel" aria-labelledby="upload-title">
            <div className="panel-head">
                <h2 id="upload-title">Upload a file</h2>
            </div>

            <form onSubmit={submit} className="upload">
                <label htmlFor="file">Choose a file</label>
                <input
                    ref={input}
                    id="file"
                    type="file"
                    onChange={(event) => setData('file', event.target.files[0] ?? null)}
                    aria-describedby="file-hint file-error"
                />
                <p id="file-hint" className="muted">
                    Up to {maxMb} MB. Allowed types: {limits.extensions.join(', ')}.
                </p>
                {errors.file && (
                    <p id="file-error" className="error" role="alert">
                        {errors.file}
                    </p>
                )}

                <button type="submit" className="btn" disabled={processing || !data.file}>
                    {processing
                        ? `Uploading ${progress ? progress.percentage : 0}%`
                        : 'Upload file'}
                </button>
            </form>
        </section>
    );
}
