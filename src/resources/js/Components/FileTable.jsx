import { useEffect } from 'react';
import { router } from '@inertiajs/react';

const STATUS_LABELS = {
    pending: 'Processing',
    ready: 'Ready',
    failed: 'Failed',
};

function formatSize(bytes) {
    if (bytes < 1024) {
        return `${bytes} B`;
    }
    if (bytes < 1024 * 1024) {
        return `${(bytes / 1024).toFixed(1)} KB`;
    }
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

export default function FileTable({ files }) {
   
    useEffect(() => {
        if (!files.some((file) => file.status === 'pending')) {
            return undefined;
        }
        const timer = setTimeout(() => router.reload({ only: ['files'] }), 2000);

        return () => clearTimeout(timer);
    }, [files]);

    function remove(file) {
        if (!window.confirm(`Delete ${file.name}? It is removed from object storage too.`)) {
            return;
        }
        router.delete(`/files/${file.id}`, { preserveScroll: true });
    }

    return (
        <section className="panel" aria-labelledby="files-title">
            <div className="panel-head">
                <h2 id="files-title">Files</h2>
            </div>

            {files.length === 0 ? (
                <p className="empty">No files yet. Choose a file on the left to upload it to object storage.</p>
            ) : (
                <div className="table-wrap">
                    <table>
                        <thead>
                            <tr>
                                <th>Name</th>
                                <th>Size</th>
                                <th>Status</th>
                                <th>SHA-256</th>
                                <th>Uploaded</th>
                                <th>
                                    <span className="sr-only">Actions</span>
                                </th>
                            </tr>
                        </thead>
                        <tbody>
                            {files.map((file) => (
                                <tr key={file.id}>
                                    <td className="name">{file.name}</td>
                                    <td>{formatSize(file.size)}</td>
                                    <td>
                                        <span className="badge" data-state={file.status}>
                                            {STATUS_LABELS[file.status] ?? file.status}
                                        </span>
                                    </td>
                                    <td className="mono">{file.checksum ? file.checksum.slice(0, 12) : '-'}</td>
                                    <td>{new Date(file.created_at).toLocaleString()}</td>
                                    <td className="actions">
                                        <a href={`/files/${file.id}/download`}>Download</a>
                                        <button type="button" className="link-danger" onClick={() => remove(file)}>
                                            Delete
                                        </button>
                                    </td>
                                </tr>
                            ))}
                        </tbody>
                    </table>
                </div>
            )}
        </section>
    );
}
