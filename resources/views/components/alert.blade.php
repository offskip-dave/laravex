<div class="alert alert-{{ type }}">
  @if($title)
    <strong>{{ title }}</strong>
  @endif
  {{ slot }}
</div>
