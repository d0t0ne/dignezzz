---
layout: default
title: dignezzz.github.io
---

<div class="language-switcher">
    <img src="https://flagcdn.com/32x24/ru.png" alt="Русский" id="ru" class="active">
    <img src="https://flagcdn.com/32x24/gb.png" alt="English" id="en">
</div>

<!-- Контент на русском -->
<div class="lang ru">
    <h1>dignezzz.github.io</h1>
    <p>Основная страница всех публикаций.</p>
    <p>Инфа будет позже.</p>
    <p>
        Мой форум: <a href="https://openode.xyz">https://openode.xyz</a><br>
        На форуме действуют подписки для доступа к Клубам (в т.ч. по Marzban): <a href="https://openode.xyz/subscriptions/">https://openode.xyz/subscriptions/</a><br>
        В клубе собраны циклы статей по полноценной установке этой и других панелей, обеспечения удобства и безопасного доступа. А также эксклюзивный дизайн подписки.
    </p>
</div>

<!-- Контент на английском -->
<div class="lang en" style="display:none;">
    <h1>dignezzz.github.io</h1>
    <p>Main page for all publications.</p>
    <p>Information will be available later.</p>
    <p>
        My forum: <a href="https://openode.xyz">https://openode.xyz</a><br>
        Subscriptions are available on the forum for access to Clubs (including Marzban): <a href="https://openode.xyz/subscriptions/">https://openode.xyz/subscriptions/</a><br>
        The club contains cycles of articles on the full installation of this and other panels, ensuring convenience and secure access. As well as an exclusive subscription design.
    </p>
</div>

<hr>

<div markdown="1">
    {% include_relative README.md %}
</div>

<script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
<script>
    $(document).ready(function() {
        // Переключение языков
        $('.language-switcher img').click(function() {
            var selectedLang = $(this).attr('id');
            $('.lang').hide();  // Скрываем все языковые блоки
            $('.' + selectedLang).show();  // Показываем только выбранный язык

            // Устанавливаем активный флажок
            $('.language-switcher img').removeClass('active');
            $(this).addClass('active');
        });
    });
</script>
