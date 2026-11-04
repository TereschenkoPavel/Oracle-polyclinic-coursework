// site.js - улучшенный пользовательский интерфейс

// Подтверждение выхода
document.addEventListener('DOMContentLoaded', function () {
    // Автоматическое скрытие уведомлений через 5 секунд
    setTimeout(function () {
        $('.alert').alert('close');
    }, 5000);

    // Подтверждение критических действий
    $('form').on('submit', function (e) {
        var confirmMessage = $(this).data('confirm');
        if (confirmMessage && !confirm(confirmMessage)) {
            e.preventDefault();
            return false;
        }
    });

    // Улучшенная работа выпадающих меню
    $('.dropdown').hover(function () {
        $(this).addClass('show');
        $(this).find('.dropdown-menu').addClass('show');
    }, function () {
        $(this).removeClass('show');
        $(this).find('.dropdown-menu').removeClass('show');
    });
});

// Обновление времени в футере каждую минуту
function updateDateTime() {
    var now = new Date();
    var options = {
        year: 'numeric',
        month: '2-digit',
        day: '2-digit',
        hour: '2-digit',
        minute: '2-digit',
        second: '2-digit'
    };
    var dateTime = now.toLocaleDateString('ru-RU', options) + ' ' +
        now.toLocaleTimeString('ru-RU', { hour: '2-digit', minute: '2-digit' });
    $('.current-time').text(dateTime);
}

setInterval(updateDateTime, 60000);
updateDateTime(); // Инициализация