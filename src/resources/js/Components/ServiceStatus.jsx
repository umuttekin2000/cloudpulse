import { useEffect, useState } from 'react';

const SERVICES = {
    mysql_primary: 'MySQL primary',
    mysql_replica: 'MySQL replica',
    redis: 'Redis',
    s3: 'Object storage',
};

function describe(check, unreachable) {
    if (!check) {
        return unreachable ? 'No data' : 'Checking';
    }
    if (check.status === 'ok') {
        return `${check.latency_ms} ms`;
    }
    return `Down: ${check.error}`;
}

export default function ServiceStatus({ pollSeconds }) {
    const [report, setReport] = useState(null);
    const [unreachable, setUnreachable] = useState(false);

    useEffect(() => {
        let active = true;

        async function load() {
            try {
                const response = await fetch('/api/status', {
                    headers: { Accept: 'application/json' },
                });
                if (!response.ok) {
                    throw new Error(`HTTP ${response.status}`);
                }
                const data = await response.json();
                if (active) {
                    setReport(data);
                    setUnreachable(false);
                }
            } catch {
                if (active) {
                    setUnreachable(true);
                }
            }
        }

        load();
        const timer = setInterval(load, pollSeconds * 1000);

        return () => {
            active = false;
            clearInterval(timer);
        };
    }, [pollSeconds]);

    let caption = 'Checking services';
    if (unreachable) {
        caption = 'The status endpoint cannot be reached';
    } else if (report) {
        const time = new Date(report.checked_at).toLocaleTimeString();
        caption = `Checked at ${time} by ${report.app.pod}`;
    }

    return (
        <section className="panel strip" aria-labelledby="services-title">
            <div className="panel-head">
                <h2 id="services-title">Services</h2>
                <p className="muted" aria-live="polite">
                    {caption}
                </p>
            </div>

            <ul className="services">
                {Object.entries(SERVICES).map(([key, label]) => {
                    const check = report?.checks?.[key];
                    const state = check ? check.status : 'unknown';

                    return (
                        <li key={key} className="service" data-state={state}>
                            <span className="dot" aria-hidden="true" />
                            <span className="service-name">{label}</span>
                            <span className="service-meta">{describe(check, unreachable)}</span>
                        </li>
                    );
                })}
            </ul>
        </section>
    );
}
