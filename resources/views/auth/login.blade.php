<!DOCTYPE html>
<html><head><title>Login</title></head>
<body>
  <h1>Login</h1>
  <form method="POST" action="/login">
    @csrf
    <label>Email <input name="email" type="email"></label>
    <label>Password <input name="password" type="password"></label>
    <button type="submit">Sign in</button>
  </form>
</body></html>
