import { Head, usePage } from '@inertiajs/react';
import ServiceStatus from '../Components/ServiceStatus';
import UploadPanel from '../Components/UploadPanel';
import FileTable from '../Components/FileTable';

export default function Dashboard({ app, limits, pollSeconds, files }) {
    const { flash } = usePage().props;

    return (
        <>
            <Head title="Dashboard" />

            <div className="shell">
                <header className="topbar">
                    <h1 className="wordmark">{app.name}</h1>
                    <dl className="build">
                        <div>
                            <dt>Environment</dt>
                            <dd>{app.env}</dd>
                        </div>
                        <div>
                            <dt>Version</dt>
                            <dd className="mono">{app.version}</dd>
                        </div>
                        <div>
                            <dt>Commit</dt>
                            <dd className="mono">{app.commit.slice(0, 7)}</dd>
                        </div>
                        <div>
                            <dt>Page served by</dt>
                            <dd className="mono">{app.pod}</dd>
                        </div>
                    </dl>
                </header>

                {flash?.success && (
                    <p className="notice" role="status">
                        {flash.success}
                    </p>
                )}

                <ServiceStatus pollSeconds={pollSeconds} />

                <div className="workspace">
                    <UploadPanel limits={limits} />
                    <FileTable files={files} />
                </div>
            </div>
        </>
    );
}
