<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Laravex</title>
    @vite(['resources/css/app.css', 'resources/js/app.js'])
    <style>
        :root { color-scheme: light dark; }
        body {
            margin: 0;
            min-height: 100vh;
            display: grid;
            place-items: center;
            font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, sans-serif;
            background: radial-gradient(circle at top, #1e293b, #020617 60%);
            color: #e2e8f0;
        }
        main { text-align: center; padding: 2rem; }
        h1 {
            font-size: clamp(2.5rem, 6vw, 4.5rem);
            letter-spacing: -0.04em;
            margin: 0 0 0.75rem;
        }
        p { margin: 0; opacity: 0.8; font-size: 1.125rem; }
    </style>
</head>
<body>
    <main>
        <h1>Laravex</h1>
        <p>Laravel 13 default setup, ported to Elixir.</p>
    </main>
</body>
</html>
